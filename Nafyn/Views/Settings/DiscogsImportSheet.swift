// Made by Lumaa

import SwiftUI
import DiscogsKit
import Safyn

struct DiscogsImportSection: View {
	@State private var showingImport = false

	var body: some View {
		Section {
			Button {
				self.showingImport = true
			} label: {
				Label(String(localized: "import-discogs"), systemImage: "opticaldisc")
					.foregroundStyle(Color.primary)
			}
			.tint(Color.primary)
		} footer: {
			Text(String(localized: "import-discogs-footer"))
		}
		.sheet(isPresented: self.$showingImport) {
			DiscogsImportSheet()
		}
	}
}

/// Reads the user's public Discogs collection with DiscogsKit (the Discogs username on their profile, or one typed
/// here), then hands its albums to `Safyn.Import.create(albums:)` and follows the import like the Apple Music one: the
/// server matches each album to MusicBrainz and requests it whole, skipping what is owned or already requested.
struct DiscogsImportSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	private enum Phase {
		case form
		case reading(page: Int, pages: Int)
		case importing(PlaylistImport)
		case done(PlaylistImport)
		case failed(String)
	}

	@State private var username = ""
	@State private var phase: Phase = .form
	@State private var task: Task<Void, Never>?

	/// Discogs allows 25 unauthenticated requests a minute.
	private static let pageInterval: Duration = .milliseconds(2500)
	private static let maxAlbums = 1000

	var body: some View {
		NavigationStack {
			Group {
				switch self.phase {
					case .form:
						self.form
					case .reading(let page, let pages):
						self.progress(value: Double(page), total: Double(max(pages, 1)), message: String(localized: "import-discogs-reading"))
					case .importing(let job):
						self.progress(value: Double(job.processed), total: Double(max(job.total, 1)), message: String(localized: "import-discogs-progress \(job.processed) \(job.total)"))
					case .done(let job):
						self.report(job)
					case .failed(let message):
						ContentUnavailableView(String(localized: "error"), systemImage: "exclamationmark.triangle", description: Text(message))
				}
			}
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "import-discogs"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "close"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
			.task {
				// the Discogs username on the profile, when there is one
				guard self.username.isEmpty, let server, let me: NafynUser = try? await server.send(User.me) else { return }
				self.username = me.discogs ?? ""
			}
			.onDisappear { self.task?.cancel() }
		}
		.sheetBackground()
	}

	private var form: some View {
		Form {
			Section {
				TextField(String(localized: "discogs-username"), text: self.$username)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
			} footer: {
				Text("import-discogs-hint")
			}
			.sheetRows()

			Section {
				Button {
					self.task = Task { await self.run() }
				} label: {
					Text("import-discogs-start")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())
				.disabled(self.username.trimmingCharacters(in: .whitespaces).isEmpty || NetworkMonitor.shared.isOffline)
				.listRowBackground(Color.clear)
			}
		}
		.scrollContentBackground(.hidden)
	}

	private func progress(value: Double, total: Double, message: String) -> some View {
		VStack(spacing: 16) {
			Spacer()
			ProgressView(value: min(value, total), total: total)
				.progressViewStyle(.linear)
				.tint(DTColor.textPrimary)
				.padding(.horizontal, 32)
			Text(message)
				.font(DTFont.text(.footnote))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				.multilineTextAlignment(.center)
				.padding(.horizontal, 32)
			Spacer()
		}
	}

	private func report(_ job: PlaylistImport) -> some View {
		List {
			Section {
				self.countRow(job.counts.requested, key: "import-discogs-requested \(job.counts.requested)", symbol: "checkmark.circle")
				self.countRow(job.counts.owned, key: "import-already-owned \(job.counts.owned)", symbol: "music.note.house")
				self.countRow(job.counts.alreadyRequested, key: "import-discogs-already-requested \(job.counts.alreadyRequested)", symbol: "clock")
				self.countRow(job.counts.notFound + job.counts.error + job.counts.unreleased, key: "import-discogs-not-found \(job.counts.notFound + job.counts.error + job.counts.unreleased)", symbol: "questionmark.circle")
			} header: {
				Text("import-complete")
			}
			.sheetRows()
		}
		.scrollContentBackground(.hidden)
	}

	@ViewBuilder
	private func countRow(_ count: Int, key: LocalizedStringKey, symbol: String) -> some View {
		if count > 0 {
			Label {
				Text(key)
			} icon: {
				Image(systemName: symbol)
			}
			.foregroundStyle(DTColor.textPrimary)
		}
	}

	// MARK: - Reading the collection

	private struct CollectionPage: Decodable {
		struct Pagination: Decodable { let pages: Int? }
		struct Release: Decodable {
			struct Info: Decodable {
				struct Artist: Decodable { let name: String?; let join: String? }
				let title: String?
				let artists: [Artist]?
			}
			let basic_information: Info?
		}
		let pagination: Pagination?
		let releases: [Release]?
	}

	/// "Artist (2)" -> "Artist" (Discogs' numbering), "Artist*" -> "Artist" (its name-variation mark), "Various" ->
	/// "Various Artists" (MusicBrainz' name) - the same cleaning as the server's `discogsCollection.ts`.
	private static func cleanArtist(_ name: String) -> String {
		var cleaned = name.replacing(/\s+\(\d+\)$/, with: "")
		if cleaned.hasSuffix("*") { cleaned.removeLast() }
		cleaned = cleaned.trimmingCharacters(in: .whitespaces)
		return cleaned.caseInsensitiveCompare("Various") == .orderedSame ? "Various Artists" : cleaned
	}

	private static func credit(_ artists: [CollectionPage.Release.Info.Artist]) -> String {
		artists.enumerated().map { index, artist in
			let name = Self.cleanArtist(artist.name ?? "")
			guard index < artists.count - 1 else { return name }
			let join = artist.join?.trimmingCharacters(in: .whitespaces) ?? ""
			return name + (join.isEmpty ? ", " : " \(join) ")
		}.joined()
	}

	private func run() async {
		let username = self.username.trimmingCharacters(in: .whitespaces)
		guard let server, !username.isEmpty else { return }

		let discogs = Discogs(name: "Nafyn", version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
		var albums: [ImportAlbum] = []
		var seen = Set<String>()
		var page: UInt = 1
		var pages = 1

		do {
			self.phase = .reading(page: 0, pages: 1)
			while albums.count < Self.maxAlbums {
				if page > 1 { try await Task.sleep(for: Self.pageInterval) }
				let response: CollectionPage? = try await discogs.get(for: UserCollections.releases(username: username, id: 0, page: page, perPage: 100))
				guard let response else { break }
				pages = response.pagination?.pages ?? 1
				for release in response.releases ?? [] {
					guard let info = release.basic_information, let title = info.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
					let artist = Self.credit(info.artists ?? [])
					guard !artist.isEmpty else { continue }
					// several pressings of one album are one request
					let key = "\(artist.lowercased())\u{0}\(title.lowercased())"
					guard seen.insert(key).inserted else { continue }
					albums.append(ImportAlbum(title: title, artist: artist))
					if albums.count >= Self.maxAlbums { break }
				}
				self.phase = .reading(page: Int(page), pages: pages)
				if Int(page) >= pages { break }
				page += 1
			}
		} catch is CancellationError {
			return
		} catch {
			self.phase = .failed(String(localized: "import-discogs-unreadable"))
			return
		}

		guard !albums.isEmpty else {
			self.phase = .failed(String(localized: "import-discogs-empty"))
			return
		}

		do {
			var job: PlaylistImport = try await server.send(Safyn.Import.create(albums: albums, source: "discogs", name: "Discogs: \(username)"))
			self.phase = .importing(job)
			while job.status == .running, !Task.isCancelled {
				try await Task.sleep(for: .seconds(3))
				job = try await server.send(Safyn.Import.get(id: job.id))
				self.phase = job.status == .running ? .importing(job) : .done(job)
			}
		} catch is CancellationError {
			return
		} catch {
			self.phase = .failed(error.localizedDescription)
		}
	}
}
