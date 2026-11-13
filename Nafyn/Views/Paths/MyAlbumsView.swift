// Made by Lumaa

import SwiftUI
import Safyn

struct MyAlbumsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<AlbumRow>? = nil
	@State private var toast = ToastState()
	@State private var selection = BulkSelection()
	@State private var isConfirmingBulkDelete = false
	@State private var isConfirmingBulkDeleteDownloads = false
	@State private var searchText = ""
	@State private var sort: LibrarySort = .added

	/// The search and order `paginator` was loaded for, so re-appearing doesn't load the same list again.
	@State private var loadedKey: ListKey? = nil

	/// What the list is asked for; a change starts it over from the server.
	private struct ListKey: Equatable {
		var search: String
		var sort: LibrarySort
	}

	private var listKey: ListKey {
		ListKey(search: self.searchText.trimmingCharacters(in: .whitespacesAndNewlines), sort: self.sort)
	}

	var body: some View {
		ScrollView {
			if let paginator {
				FoldGrid(spacing: 16) {
					ForEach(self.mergedAlbums) { album in
						self.card(album)
							.onAppear { paginator.loadNextPageIfNeeded(currentItem: album) }
					}
				}
				.padding()

				if paginator.isLoadingPage {
					SkeletonMusicGrid(count: 2)
						.padding(.horizontal)
				} else if self.mergedAlbums.isEmpty, !self.listKey.search.isEmpty, paginator.error == nil {
					Text("no-results")
						.font(DTFont.system(18))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						.frame(maxWidth: .infinity)
						.padding(.top, 40)
				}
			} else {
				SkeletonMusicGrid()
					.padding()
			}
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn(maxWidth: DTLayout.gridWidth)
		.background(DTColor.background.ignoresSafeArea())
		// `id` runs this again on every change of the search or the order and cancels the previous run, so the
		// sleep is the debounce; the first run (no list yet) goes straight through. SwiftUI also restarts it
		// each time the view re-appears (coming back from a screen pushed on top of it): the list already
		// loaded for this search and order is kept then, scroll position and all, instead of starting over.
		.task(id: self.listKey) {
			guard let server else { return }
			if self.paginator != nil, self.loadedKey == self.listKey { return }
			if self.paginator != nil {
				try? await Task.sleep(for: .milliseconds(350))
				guard !Task.isCancelled else { return }
			}
			let key = self.listKey
			let paginator = Paginator<AlbumRow> { page, limit in
				try await server.fetchLibraryPage(path: "/api/v1/library/albums", page: page, limit: limit, query: key.search, sort: key.sort)
			}
			self.paginator = paginator
			self.loadedKey = nil
			await paginator.reset()
			// a run cancelled mid-load (left before the first page came) loads again when the view is back
			if !Task.isCancelled {
				self.loadedKey = key
			}
		}
		.searchable(text: self.$searchText, prompt: String(localized: "search-albums"))
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				LibrarySortMenu(sort: self.$sort)
			}

			// sorting and selecting have nothing to do with one another
			ToolbarSpacer(.fixed, placement: .primaryAction)
		}
		.onReceive(NotificationCenter.default.publisher(for: .nafynLibraryChanged)) { _ in
			Task { await self.paginator?.reset() }
		}
		.refreshable {
			await self.paginator?.reset()
		}
		.navigationTitle(String(localized: "albums"))
		.bulkSelectionSubtitle(self.selection)
		.bulkSelectionToolbar(self.selection, allIds: self.mergedAlbums.map(\.id)) {
			self.bulkActions
		}
		.toast(self.toast)
		.alert(
			String(localized: "delete-albums-confirm \(self.selection.count)"),
			isPresented: self.$isConfirmingBulkDelete
		) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.bulkDelete()
			}
		}
		.alert(String(localized: "delete-selected-downloads-confirm"), isPresented: self.$isConfirmingBulkDeleteDownloads) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				for album in self.selectedAlbums {
					DownloadManager.shared.deleteDownloads(trackIds: DownloadManager.shared.downloadedTrackIds(albumId: album.id))
				}
				self.selection.end()
			}
		}
	}

	/// One album: opens it, or ticks it while selecting.
	@ViewBuilder
	private func card(_ album: AlbumRow) -> some View {
		let content = MusicCard(.album(album), onRemoved: { self.paginator?.remove(where: { $0.id == album.id }) })
			.overlay(alignment: .topTrailing) {
				if DownloadManager.shared.downloads.contains(where: { $0.albumId == album.id }) {
					Image(systemName: "arrow.down.circle.fill")
						.foregroundStyle(DTColor.textPrimary)
						.padding(6)
						.background(Circle().fill(DTColor.surfaceSelect))
						.padding(6)
				}
			}

		if self.selection.isActive {
			// a plain button instead of the link: the tap ticks the card
			Button {
				self.selection.toggle(album.id)
			} label: {
				content
					.overlay(alignment: .topLeading) {
						SelectionMark(isSelected: self.selection.contains(album.id))
							.padding(6)
					}
					.opacity(self.selection.contains(album.id) ? 1 : 0.7)
			}
			.buttonStyle(.plain)
		} else {
			NavigationLink(value: Navigator.Paths.libraryAlbum(id: album.id)) {
				content
			}
			.buttonStyle(.plain)
		}
	}

	/// The ticked albums, as listed.
	private var selectedAlbums: [AlbumRow] {
		self.mergedAlbums.filter { self.selection.contains($0.id) }
	}

	@ViewBuilder
	private var bulkActions: some View {
		let albums = self.selectedAlbums

		Button {
			self.addToPlaylist(albums)
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		BulkPinButton(targets: albums.map { .album($0.id) }, toast: self.toast) {
			self.selection.end()
		}

		Button {
			for album in albums {
				DownloadManager.shared.downloadAlbum(id: album.id, title: album.title)
			}
			self.selection.end()
		} label: {
			Label(String(localized: "download"), systemImage: "arrow.down.circle")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)

		if albums.contains(where: { !DownloadManager.shared.downloadedTrackIds(albumId: $0.id).isEmpty }) {
			Button(role: .destructive) {
				self.isConfirmingBulkDeleteDownloads = true
			} label: {
				Label(String(localized: "delete-downloads"), systemImage: "arrow.down.circle.fill")
			}
			.tint(DTColor.dangerText)
		}

		Button(role: .destructive) {
			self.isConfirmingBulkDelete = true
		} label: {
			Label(String(localized: "delete"), systemImage: "trash")
		}
		.tint(DTColor.dangerText)
		.disabled(NetworkMonitor.shared.isOffline)
	}

	/// Opens the playlist picker with every owned track of the ticked albums.
	private func addToPlaylist(_ albums: [AlbumRow]) {
		guard let server else { return }
		let ids = albums.map(\.id)
		Task { @MainActor in
			do {
				let trackIds = try await BulkActions.trackIds(ofAlbums: ids, server: server)
				guard !trackIds.isEmpty else { return }
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: trackIds)
				self.selection.end()
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func bulkDelete() {
		guard let server else { return }
		let ids = Array(self.selection.ids)
		Task { @MainActor in
			let result = await BulkActions.removeAlbums(ids, server: server)
			self.paginator?.remove(where: { result.succeeded.contains($0.id) })
			if let error = result.error {
				self.toast.failure(error)
			}
			await PinStore.shared.refresh(server: server)
			self.selection.end()
		}
	}

	/// `paginator.items` merged with every album that has at least one downloaded track, so offline
	/// albums stay visible instead of this screen showing an empty grid while offline. Albums not yet
	/// seen from the server (download-only) are synthesized from their downloaded tracks' cached metadata.
	private var mergedAlbums: [AlbumRow] {
		var seen: Set<String> = []
		var result: [AlbumRow] = []

		for album in self.paginator?.items ?? [] where seen.insert(album.id).inserted {
			result.append(album)
		}

		let downloadedByAlbum = Dictionary(grouping: DownloadManager.shared.downloads, by: \.albumId)
		for (albumId, tracks) in downloadedByAlbum where seen.insert(albumId).inserted {
			guard let first = tracks.first else { continue }
			let downloaded = AlbumRow(
				id: albumId,
				mbId: "",
				title: first.album ?? first.artistName,
				artistName: first.artistName,
				artistMbid: nil,
				coverArt: first.coverArt,
				releaseDate: nil,
				duration: tracks.reduce(0) { $0 + $1.duration },
				trackCount: tracks.count,
				addedAt: Int64((tracks.map(\.downloadedAt).max() ?? .now).timeIntervalSince1970 * 1000)
			)
			// the server already narrowed its own rows; the downloaded ones are matched here
			if downloaded.matchesLibrarySearch(self.listKey.search) {
				result.append(downloaded)
			}
		}

		return result.sorted { self.sort.areInOrder($0, $1) }
	}
}
