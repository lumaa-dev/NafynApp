// Made by Lumaa

import SwiftUI
import MusicKit
import Safyn

/// Imports one Apple Music library playlist as Nafyn download requests.
///
/// `MusicKit` and `Safyn` both declare `Playlist`, `Track`, and `Request` types, so every reference to
/// one of those needs an explicit module prefix in this file to disambiguate.
///
/// Flow: (1) resolve every track's ISRC via `MusicKit`, splitting into a matched-ISRC list and a
/// missing-ISRC list; (2) look each ISRC up against the Nafyn server with `Safyn.Track.getByIsrc`; (3)
/// file a `Safyn.Request.create` for every track that resolved. Tracks with no ISRC can't be matched
/// server-side, so they're collected separately and shown to the user instead of silently dropped.
struct AppleMusicImportSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.server) private var server: NafynServer?

	private enum Phase {
		case loadingPlaylists
		case pickingPlaylist([MusicKit.Playlist])
		case importing(step: ImportStep, progress: Double, total: Double)
		case missingIsrc([MissingTrack])
		case finished(importedCount: Int)
		case failed(String)
	}

	private enum ImportStep {
		case fetchingIsrc
		case fetchingSongs
		case creatingRequests

		var message: String {
			switch self {
				case .fetchingIsrc: return String(localized: "import-step-fetch-isrc")
				case .fetchingSongs: return String(localized: "import-step-fetch-songs")
				case .creatingRequests: return String(localized: "import-step-create-requests")
			}
		}
	}

	private struct MissingTrack: Identifiable {
		let id = UUID()
		let title: String
		let artist: String
	}

	@State private var phase: Phase = .loadingPlaylists

	var body: some View {
		NavigationStack {
			Group {
				switch self.phase {
					case .loadingPlaylists:
						List {
							SkeletonTrackRows(showsCover: false)
						}
						.listStyle(.plain)

					case .pickingPlaylist(let playlists):
						self.playlistPicker(playlists)

					case .importing(let step, let progress, let total):
						self.importProgress(step: step, progress: progress, total: total)

					case .missingIsrc(let tracks):
						self.missingIsrcList(tracks)

					case .finished(let count):
						self.finishedView(count: count)

					case .failed(let message):
						self.failedView(message)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "import-apple-music"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "close"))
					.tint(Color.primary)
				}
			}
		}
		.interactiveDismissDisabled()
		.task {
			await self.loadPlaylists()
		}
	}

	@ViewBuilder
	private func playlistPicker(_ playlists: [MusicKit.Playlist]) -> some View {
		if playlists.isEmpty {
			ContentUnavailableView(String(localized: "no-playlists"), systemImage: "music.note.list")
		} else {
			List(playlists) { playlist in
				Button {
					Task {
						await self.startImport(playlist: playlist)
					}
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(playlist.name)
							.foregroundStyle(DTColor.textPrimary)

						if let count = playlist.tracks?.count {
							Text("\(count)")
								.font(.footnote)
								.foregroundStyle(DTColor.textPrimary.opacity(0.55))
						}
					}
				}
				.tint(Color.primary)
				.disabled(NetworkMonitor.shared.isOffline)
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
		}
	}

	@ViewBuilder
	private func importProgress(step: ImportStep, progress: Double, total: Double) -> some View {
		VStack(spacing: 16) {
			Spacer()

			ProgressView(value: progress, total: max(total, 1))
				.progressViewStyle(.linear)
				.tint(DTColor.textPrimary)
				.padding(.horizontal, 32)

			Text(step.message)
				.font(.footnote)
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			Spacer()
		}
	}

	@ViewBuilder
	private func missingIsrcList(_ tracks: [MissingTrack]) -> some View {
		List {
			Section {
				Text(String(localized: "error-import-isrc"))
					.foregroundStyle(DTColor.buttonDanger)
			}

			Section {
				ForEach(tracks) { track in
					VStack(alignment: .leading, spacing: 2) {
						Text(track.title)
							.foregroundStyle(DTColor.textPrimary)
						Text(track.artist)
							.font(.footnote)
							.foregroundStyle(DTColor.textPrimary.opacity(0.55))
					}
				}
			}
		}
		.scrollContentBackground(.hidden)
	}

	@ViewBuilder
	private func finishedView(count: Int) -> some View {
		ContentUnavailableView(
			String(localized: "import-complete"),
			systemImage: "checkmark.circle",
			description: Text("\(count)")
		)
	}

	@ViewBuilder
	private func failedView(_ message: String) -> some View {
		ContentUnavailableView(
			String(localized: "error"),
			systemImage: "exclamationmark.triangle",
			description: Text(message)
		)
	}

	private func loadPlaylists() async {
		let status = await MusicAuthorization.request()
		guard status == .authorized else {
			self.phase = .failed(String(localized: "error-apple-music-denied"))
			return
		}

		do {
			let request = MusicLibraryRequest<MusicKit.Playlist>()
			let response = try await request.response()
			self.phase = .pickingPlaylist(Array(response.items))
		} catch {
			self.phase = .failed(error.localizedDescription)
		}
	}

	private func startImport(playlist: MusicKit.Playlist) async {
		guard let server else {
			self.phase = .failed(String(localized: "error-unauthenticated"))
			return
		}

		do {
			// Step 1: resolve every track's ISRC, splitting matched from missing.
			self.phase = .importing(step: .fetchingIsrc, progress: 0, total: 1)
			let tracks = try await Self.allTracks(of: playlist)
			let (isrcs, missing) = await self.resolveISRCs(for: tracks)

			// Step 2: turn each ISRC into Nafyn track data (a few lookups at a time).
			var converted: [TrackDetail] = []
			var unmatched: [MissingTrack] = []
			let lookups = await Self.concurrentMap(isrcs, width: 6, onProgress: { done in
				self.phase = .importing(step: .fetchingSongs, progress: Double(done), total: Double(max(isrcs.count, 1)))
			}) { (isrc: Song.ISRCEntry) -> TrackDetail? in
				try? await server.send(Safyn.Track.getByIsrc(isrc: isrc.isrc)) as TrackDetail
			}
			for (entry, detail) in zip(isrcs, lookups) {
				if let detail {
					converted.append(detail)
				} else {
					// Apple Music knows the ISRC, Nafyn doesn't: still something the user should see.
					unmatched.append(MissingTrack(title: entry.title, artist: entry.artist))
				}
			}

			guard !converted.isEmpty || isrcs.isEmpty else {
				self.phase = .failed(String(localized: "error-import-no-matches"))
				return
			}

			// Step 3: file a download request for each resolved track.
			var importedCount = 0
			for (index, detail) in converted.enumerated() {
				self.phase = .importing(step: .creatingRequests, progress: Double(index), total: Double(max(converted.count, 1)))
				if let _: NafynRequest = try? await server.send(Safyn.Request.create(id: detail.info.id, type: .track)) {
					importedCount += 1
				}
			}

			let notImported = missing + unmatched
			if !notImported.isEmpty {
				self.phase = .missingIsrc(notImported)
			} else {
				self.phase = .finished(importedCount: importedCount)
			}
		} catch {
			self.phase = .failed(error.localizedDescription)
		}
	}

	// MARK: - MusicKit lookups

	/// Every track of `playlist`, following `nextBatch()` — `with(.tracks)` only loads the first page, so
	/// anything past it (~100 songs) used to be silently ignored.
	private static func allTracks(of playlist: MusicKit.Playlist) async throws -> [MusicKit.Track] {
		let detailed = try await playlist.with(.tracks)
		guard var collection = detailed.tracks else { return [] }

		var result = Array(collection)
		while collection.hasNextBatch, let next = try await collection.nextBatch() {
			result.append(contentsOf: next)
			collection = next
		}
		return result
	}

	/// The catalog ID behind a song. A *library* song's own `id` is a library ID (`i.…`) that no catalog
	/// request understands — looking it up as a catalog ID (the previous approach) always came back empty,
	/// so every track ended up "missing its ISRC". The catalog ID lives in the song's play parameters.
	private static func catalogID(of song: Song) -> String? {
		guard let parameters = song.playParameters,
			  let data = try? JSONEncoder().encode(parameters),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		if let catalogId = json["catalogId"] as? String { return catalogId }
		if (json["isLibrary"] as? Bool) != true, let id = json["id"] as? String { return id }
		return nil
	}

	private static func normalized(_ text: String) -> String {
		text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
			.filter { $0.isLetter || $0.isNumber }
	}

	/// ISRC resolution, cheapest first: the song's own `isrc` → batched catalog lookup by catalog ID (from
	/// the play parameters) → catalog text search on title + artist for anything still unresolved.
	private func resolveISRCs(for tracks: [MusicKit.Track]) async -> (isrcs: [Song.ISRCEntry], missing: [MissingTrack]) {
		var songs: [Song] = []
		var missing: [MissingTrack] = []
		for track in tracks {
			switch track {
				case .song(let song):
					songs.append(song)
				case .musicVideo(let video):
					missing.append(MissingTrack(title: video.title, artist: video.artistName))
				@unknown default:
					break
			}
		}

		let total = Double(max(songs.count, 1))
		var resolved: [Int: String] = [:]
		var catalogIds: [Int: String] = [:]

		for (index, song) in songs.enumerated() {
			if let isrc = song.isrc, !isrc.isEmpty {
				resolved[index] = isrc
			} else if let id = Self.catalogID(of: song) {
				catalogIds[index] = id
			}
		}
		self.phase = .importing(step: .fetchingIsrc, progress: Double(resolved.count), total: total)

		// Batched catalog lookup by ID.
		let uniqueIds = Array(Set(catalogIds.values))
		var isrcByCatalogId: [String: String] = [:]
		for chunk in stride(from: 0, to: uniqueIds.count, by: 50).map({ Array(uniqueIds[$0..<min($0 + 50, uniqueIds.count)]) }) {
			do {
				let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
				for catalogSong in try await request.response().items {
					if let isrc = catalogSong.isrc { isrcByCatalogId[catalogSong.id.rawValue] = isrc }
				}
			} catch {
				print("[AppleMusicImport] catalog lookup failed for \(chunk.count) ids: \(error)")
			}
			self.phase = .importing(step: .fetchingIsrc, progress: Double(resolved.count + isrcByCatalogId.count), total: total)
		}
		for (index, id) in catalogIds {
			if let isrc = isrcByCatalogId[id] { resolved[index] = isrc }
		}

		// Text search fallback for what's left (songs with no catalog counterpart ID, or no ISRC on it).
		let unresolved = songs.indices.filter { resolved[$0] == nil }
		let searched = await Self.concurrentMap(unresolved, width: 5, onProgress: { done in
			self.phase = .importing(step: .fetchingIsrc, progress: Double(resolved.count + done), total: total)
		}) { (index: Int) -> String? in
			await Self.searchISRC(for: songs[index])
		}
		for (index, isrc) in zip(unresolved, searched) {
			if let isrc { resolved[index] = isrc }
		}

		var seen: Set<String> = []
		var entries: [Song.ISRCEntry] = []
		for (index, song) in songs.enumerated() {
			if let isrc = resolved[index] {
				if seen.insert(isrc).inserted {
					entries.append(Song.ISRCEntry(isrc: isrc, title: song.title, artist: song.artistName))
				}
			} else {
				missing.append(MissingTrack(title: song.title, artist: song.artistName))
			}
		}
		return (entries, missing)
	}

	/// Catalog search for `song` by title + artist; accepts a hit whose normalized title and artist match,
	/// else one whose title matches and duration is within 3 seconds.
	private static func searchISRC(for song: Song) async -> String? {
		var request = MusicCatalogSearchRequest(term: "\(song.title) \(song.artistName)", types: [Song.self])
		request.limit = 5
		guard let candidates = try? await request.response().songs else { return nil }

		let title = Self.normalized(song.title)
		let artist = Self.normalized(song.artistName)
		let exact = candidates.first { Self.normalized($0.title) == title && Self.normalized($0.artistName) == artist && $0.isrc != nil }
		let close = candidates.first { candidate in
			guard Self.normalized(candidate.title) == title, candidate.isrc != nil else { return false }
			guard let a = candidate.duration, let b = song.duration else { return true }
			return abs(a - b) <= 3
		}
		return (exact ?? close)?.isrc
	}

	/// `transform` over `items`, `width` at a time, results in input order. `onProgress` gets the running
	/// count of finished items (on the main actor).
	private static func concurrentMap<Input: Sendable, Output: Sendable>(
		_ items: [Input],
		width: Int,
		onProgress: @MainActor @escaping (Int) -> Void,
		_ transform: @escaping @Sendable (Input) async -> Output
	) async -> [Output] {
		var results = [Output?](repeating: nil, count: items.count)
		var done = 0

		await withTaskGroup(of: (Int, Output).self) { group in
			var next = 0
			func enqueue() {
				guard next < items.count else { return }
				let index = next, item = items[next]
				next += 1
				group.addTask { (index, await transform(item)) }
			}

			for _ in 0..<min(width, items.count) { enqueue() }
			while let (index, output) = await group.next() {
				results[index] = output
				done += 1
				await onProgress(done)
				enqueue()
			}
		}
		return results.compactMap { $0 }
	}
}

private extension Song {
	/// A resolved ISRC plus the song it came from, so a failed Nafyn lookup can still be reported by name.
	struct ISRCEntry: Sendable {
		let isrc: String
		let title: String
		let artist: String
	}
}
