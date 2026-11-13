// Made by Lumaa

import SwiftUI
import Safyn

/// Puts an owned track on another album: "Bad Decisions" came out as a single and belongs on "The New
/// Abnormal". Two steps: the user first picks the album of their own library the track belongs to
/// (``ChangeAlbumLibraryStep``), which is then looked up on MusicBrainz by its title and artist
/// (``ChangeAlbumSearchStep``: searching the artist alone is unreliable when they have many releases). Picking
/// the result runs `Library.changeAlbum`: the server takes the album's title, cover, date and the track's place
/// on it, and moves the file. Mirrors the web app's `ChangeAlbumModal.vue`. The first step can be skipped ("Search
/// online"): the album the track belongs on is often not in the library at all.
struct ChangeAlbumSheet: View {
	@Environment(\.server) private var server: NafynServer?

	let trackId: String

	/// The search step, from a library album or straight away (`nil`: the query starts from the track's artist).
	fileprivate struct SearchStep: Hashable {
		let libraryAlbum: AlbumRow?
	}

	@State private var track: MediaRow? = nil
	@State private var path: [SearchStep] = []

	var body: some View {
		NavigationStack(path: self.$path) {
			ChangeAlbumLibraryStep(track: self.track) { album in
				self.path.append(SearchStep(libraryAlbum: album))
			} onSkip: {
				self.path.append(SearchStep(libraryAlbum: nil))
			}
			.navigationDestination(for: SearchStep.self) { step in
				ChangeAlbumSearchStep(trackId: self.trackId, track: self.track, libraryAlbum: step.libraryAlbum)
			}
		}
		.sheetBackground()
		.task {
			guard self.track == nil, let server else { return }
			self.track = (try? await server.send(Library.track(id: self.trackId)) as LibraryTrackResponse)?.row
		}
	}
}

// MARK: - Step 1: the library's albums

/// The albums the user owns, searchable. Tapping one moves on to looking it up in the catalog.
private struct ChangeAlbumLibraryStep: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	let track: MediaRow?
	let onPick: (AlbumRow) -> Void
	/// Straight to the online search, without picking a library album first.
	let onSkip: () -> Void

	@State private var paginator: Paginator<AlbumRow>? = nil
	@State private var searchText = ""

	private var search: String {
		self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var body: some View {
		List {
			if let track {
				Text("change-album-pick \(track.title) \(track.artistName)")
					.font(DTFont.system(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.listRowBackground(Color.clear)
			}

			Button {
				self.onSkip()
			} label: {
				Label(String(localized: "change-album-search-online"), systemImage: "magnifyingglass")
					.font(DTFont.system(17))
					.foregroundStyle(DTColor.textPrimary)
			}
			.tint(Color.primary)
			.listRowBackground(Color.clear)

			if let paginator {
				ForEach(paginator.items) { album in
					Button {
						self.onPick(album)
					} label: {
						self.row(album)
					}
					.listRowBackground(Color.clear)
					.onAppear { paginator.loadNextPageIfNeeded(currentItem: album) }
				}

				if paginator.isLoadingPage {
					SkeletonTrackRows(count: paginator.items.isEmpty ? 6 : 2)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				} else if let error = paginator.error, paginator.items.isEmpty {
					Text(error.localizedDescription)
						.font(DTFont.system(16))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
						.frame(maxWidth: .infinity)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				} else if paginator.items.isEmpty {
					Text("no-results")
						.font(DTFont.system(18))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						.frame(maxWidth: .infinity)
						.padding(.top, 30)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}
			} else {
				SkeletonTrackRows(count: 6)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn()
		.background(DTColor.background.ignoresSafeArea())
		.navigationTitle(String(localized: "change-album"))
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: self.$searchText, prompt: String(localized: "search-albums"))
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button {
					self.dismiss()
				} label: {
					Label(String(localized: "cancel"), systemImage: "xmark")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
			}
		}
		// `id` runs this again on every edit of the search and cancels the previous run, so the sleep is the
		// debounce: one request once typing pauses, not one per keystroke. The first run goes straight through.
		.task(id: self.search) {
			guard let server else { return }
			if self.paginator != nil {
				try? await Task.sleep(for: .milliseconds(500))
				guard !Task.isCancelled else { return }
			}
			let query = self.search
			let paginator = Paginator<AlbumRow> { page, limit in
				try await server.fetchLibraryPage(path: "/api/v1/library/albums", page: page, limit: limit, query: query, sort: .added)
			}
			self.paginator = paginator
			await paginator.reset()
		}
	}

	private func row(_ album: AlbumRow) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: album.coverArt.flatMap { URL(string: $0) })
				.frame(width: 48, height: 48)

			VStack(alignment: .leading, spacing: 2) {
				Text(album.title)
					.font(DTFont.system(16, weight: .semibold))
					.lineLimit(1)
				Text(ChangeAlbumDetails.line(artist: album.artistName, releaseDate: album.releaseDateValue))
					.font(DTFont.system(13))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}

			Spacer()

			if album.id == self.track?.albumId {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.accessibilityLabel(String(localized: "current"))
			} else {
				Image(systemName: "chevron.right")
					.font(DTFont.system(14, weight: .semibold))
					.foregroundStyle(DTColor.textPrimary.opacity(0.4))
			}
		}
		.contentShape(Rectangle())
	}
}

// MARK: - Step 2: the catalog

/// The catalog's albums matching the library album picked in step 1 (searched right away), editable. Picking
/// one moves the track there.
private struct ChangeAlbumSearchStep: View {
	@Environment(\.server) private var server: NafynServer?

	let trackId: String
	let track: MediaRow?
	let libraryAlbum: AlbumRow?

	@State private var query: String
	@State private var albums: [MediaInfo] = []
	@State private var isSearching = false
	@State private var hasSearched = false
	@State private var pending: MediaInfo? = nil
	@State private var movingTo: String? = nil
	@State private var toast = ToastState()

	/// Whether a search was already started: every one after the first waits for typing to pause.
	@State private var hasStartedSearching = false
	@State private var lastSearched = ""

	init(trackId: String, track: MediaRow?, libraryAlbum: AlbumRow?) {
		self.trackId = trackId
		self.track = track
		self.libraryAlbum = libraryAlbum
		// skipped the library: start from the track's artist, the person types the album
		self._query = State(initialValue: libraryAlbum.map { "\($0.title) \($0.artistName)" } ?? track.map { "\($0.artistName) " } ?? "")
	}

	var body: some View {
		List {
			if let track {
				Text("change-album-intro \(track.title) \(track.artistName)")
					.font(DTFont.system(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.listRowBackground(Color.clear)
			}

			if self.isSearching && self.albums.isEmpty {
				SkeletonTrackRows(count: 5)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			} else if self.hasSearched && self.albums.isEmpty {
				Text("no-results")
					.font(DTFont.system(18))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					.frame(maxWidth: .infinity)
					.padding(.top, 30)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}

			ForEach(self.albums, id: \.id) { album in
				Button {
					self.pending = album
				} label: {
					self.row(album)
				}
				.disabled(self.movingTo != nil || NetworkMonitor.shared.isOffline)
				.listRowBackground(Color.clear)
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn()
		.background(DTColor.background.ignoresSafeArea())
		.navigationTitle(String(localized: "change-album"))
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: self.$query, prompt: String(localized: "search-albums"))
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button {
					// the whole sheet, not just this step
					Navigator.shared.sheet = nil
				} label: {
					Label(String(localized: "cancel"), systemImage: "xmark")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
			}
		}
		.toast(self.toast)
		.alert(
			self.pending.map { String(localized: "change-album-confirm \(self.track?.title ?? "") \($0.title)") } ?? "",
			isPresented: Binding(get: { self.pending != nil }, set: { if !$0 { self.pending = nil } }),
			presenting: self.pending
		) { album in
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "move")) {
				self.move(to: album)
			}
		}
		// Searches as the user types. `id` re-runs the task on every edit and cancels the previous run, so its
		// sleep is the debounce: a request once typing pauses, never one per keystroke. The pre-filled query
		// goes straight through; the flag flips before the request starts, so edits made while it is in flight
		// already wait.
		.task(id: self.query) {
			let text = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
			guard text.count >= 2 else {
				self.albums = []
				self.hasSearched = false
				self.lastSearched = ""
				return
			}
			guard text != self.lastSearched else { return }

			if self.hasStartedSearching {
				try? await Task.sleep(for: .milliseconds(600))
				guard !Task.isCancelled else { return }
			}
			self.hasStartedSearching = true
			await self.search(text)
		}
	}

	private func row(_ album: MediaInfo) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: album.coverArt.flatMap { URL(string: $0) })
				.frame(width: 48, height: 48)

			VStack(alignment: .leading, spacing: 2) {
				Text(album.title)
					.font(DTFont.system(16, weight: .semibold))
					.lineLimit(1)
				Text(ChangeAlbumDetails.line(artist: album.artist.name, releaseDate: album.releaseDate))
					.font(DTFont.system(13))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}

			Spacer()

			if self.movingTo == album.id {
				ProgressView()
					.tint(DTColor.textPrimary)
			} else if album.id == self.track?.albumId {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.accessibilityLabel(String(localized: "current"))
			}
		}
		.contentShape(Rectangle())
	}

	private func search(_ text: String) async {
		guard let server else { return }
		self.isSearching = true
		defer { self.isSearching = false }

		do {
			let result: SearchResult = try await server.send(Search.search(q: text, filter: .album, limit: 15))
			guard !Task.isCancelled else { return }
			self.albums = result.albums
			self.hasSearched = true
			self.lastSearched = text
		} catch {
			guard !Task.isCancelled else { return }
			self.albums = []
			self.toast.failure(error)
		}
	}

	private func move(to album: MediaInfo) {
		guard let server, self.movingTo == nil else { return }
		self.movingTo = album.id

		Task { @MainActor in
			defer { self.movingTo = nil }
			do {
				_ = try await server.send(Library.changeAlbum(id: self.trackId, albumId: album.id)) as MediaRow
				// the Tracks and Albums lists show the new album, and the old one is gone if it was left empty
				NotificationCenter.default.post(name: .nafynLibraryChanged, object: nil)
				Navigator.shared.sheet = nil
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

private enum ChangeAlbumDetails {
	/// "Artist · 2020".
	static func line(artist: String, releaseDate: Date?) -> String {
		var parts = [artist]
		if let releaseDate {
			parts.append(String(Calendar(identifier: .gregorian).component(.year, from: releaseDate)))
		}
		return parts.joined(separator: " · ")
	}
}
