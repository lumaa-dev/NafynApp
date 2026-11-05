// Made by Lumaa

import SwiftUI
import Safyn

struct MyTracksView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var toast = ToastState()
	@State private var pendingDelete: MediaRow? = nil
	@State private var paginator: Paginator<MediaRow>? = nil
	@State private var selection = BulkSelection()
	@State private var isConfirmingBulkDelete = false
	@State private var isConfirmingBulkDeleteDownloads = false
	@State private var searchText = ""
	@State private var sort: LibrarySort = .added

	/// What the list is asked for; a change starts it over from the server.
	private struct ListKey: Equatable {
		var search: String
		var sort: LibrarySort
	}

	private var listKey: ListKey {
		ListKey(search: self.searchText.trimmingCharacters(in: .whitespacesAndNewlines), sort: self.sort)
	}

	private var isSearching: Bool {
		!self.listKey.search.isEmpty
	}

	var body: some View {
		Group {
			if let paginator {
				List {
					ForEach(self.mergedTracks) { track in
						self.row(track)
							.listRowBackground(Color.clear)
							.onAppear { paginator.loadNextPageIfNeeded(currentItem: track) }
					}

					if paginator.isLoadingPage {
						SkeletonTrackRows(count: self.mergedTracks.isEmpty ? 8 : 2)
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
					}

					if self.mergedTracks.isEmpty, self.isSearching, !paginator.isLoadingPage, paginator.error == nil {
						Text("no-results")
							.font(DTFont.system(18))
							.foregroundStyle(DTColor.textPrimary.opacity(0.5))
							.frame(maxWidth: .infinity)
							.padding(.top, 40)
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
					}

					if let error = paginator.error, self.mergedTracks.isEmpty {
						VStack(spacing: 12) {
							Text(error.localizedDescription)
								.font(DTFont.system(16))
								.foregroundStyle(DTColor.textPrimary.opacity(0.7))
								.multilineTextAlignment(.center)

							Button(String(localized: "retry")) {
								Task { await paginator.reset() }
							}
							.buttonStyle(.hollow())
						}
						.frame(maxWidth: .infinity)
						.padding()
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
					}
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
				.scrollEdgeEffectStyle(.soft, for: .all)
				.contentColumn()
				.background(DTColor.background.ignoresSafeArea())
				.refreshable {
					await paginator.reset()
				}
			} else {
				List {
					SkeletonTrackRows()
						.listRowBackground(Color.clear)
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
			}
		}
		// `id` runs this again on every change of the search or the order and cancels the previous run, so the
		// sleep is the debounce; the first run (no list yet) goes straight through
		.task(id: self.listKey) {
			guard let server else { return }
			if self.paginator != nil {
				try? await Task.sleep(for: .milliseconds(350))
				guard !Task.isCancelled else { return }
			}
			let key = self.listKey
			let paginator = Paginator<MediaRow> { page, limit in
				try await server.fetchLibraryPage(path: "/api/v1/library/tracks", page: page, limit: limit, query: key.search, sort: key.sort)
			}
			self.paginator = paginator
			await paginator.reset()
		}
		.searchable(text: self.$searchText, prompt: String(localized: "search-tracks"))
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
		.navigationTitle(String(localized: "tracks"))
		.bulkSelectionSubtitle(self.selection)
		.bulkSelectionToolbar(self.selection, allIds: self.mergedTracks.map(\.id)) {
			self.bulkActions
		}
		.toast(self.toast)
		.alert(
			String(localized: "delete-tracks-confirm \(self.selection.count)"),
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
				DownloadManager.shared.deleteDownloads(trackIds: self.selectedTracks.map(\.id))
				self.selection.end()
			}
		}
		.alert(
			String(localized: "delete-track-confirm"),
			isPresented: Binding(get: { self.pendingDelete != nil }, set: { if !$0 { self.pendingDelete = nil } }),
			presenting: self.pendingDelete
		) { track in
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.delete(track)
			}
		}
	}

	/// The ticked tracks, as listed.
	private var selectedTracks: [MediaRow] {
		self.mergedTracks.filter { self.selection.contains($0.id) }
	}

	@ViewBuilder
	private var bulkActions: some View {
		let tracks = self.selectedTracks

		Button {
			Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: tracks.map(\.id))
			self.selection.end()
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		BulkPinButton(targets: tracks.map { .track($0.id) }, toast: self.toast) {
			self.selection.end()
		}

		Button {
			for track in tracks where !DownloadManager.shared.isDownloaded(trackId: track.id) {
				DownloadManager.shared.downloadTrack(track)
			}
			self.selection.end()
		} label: {
			Label(String(localized: "download"), systemImage: "arrow.down.circle")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline || tracks.allSatisfy { DownloadManager.shared.isDownloaded(trackId: $0.id) })

		if tracks.contains(where: { DownloadManager.shared.isDownloaded(trackId: $0.id) }) {
			Button(role: .destructive) {
				self.isConfirmingBulkDeleteDownloads = true
			} label: {
				Label(String(localized: "delete-downloads"), systemImage: "arrow.down.circle.fill")
			}
			.tint(DTColor.buttonDanger)
		}

		Button(role: .destructive) {
			self.isConfirmingBulkDelete = true
		} label: {
			Label(String(localized: "delete"), systemImage: "trash")
		}
		.tint(DTColor.buttonDanger)
		.disabled(NetworkMonitor.shared.isOffline)
	}

	private func bulkDelete() {
		guard let server else { return }
		let ids = Array(self.selection.ids)
		Task { @MainActor in
			let result = await BulkActions.removeTracks(ids, server: server)
			self.paginator?.remove(where: { result.succeeded.contains($0.id) })
			if let error = result.error {
				self.toast.failure(error)
			}
			await PinStore.shared.refresh(server: server)
			self.selection.end()
		}
	}

	/// `paginator.items` merged with every downloaded track, so offline tracks stay visible in the same
	/// list instead of the screen falling back to a bare network-error message while offline.
	private var mergedTracks: [MediaRow] {
		var seen: Set<String> = []
		var result: [MediaRow] = []

		for track in self.paginator?.items ?? [] where seen.insert(track.id).inserted {
			result.append(track)
		}
		// the server already narrowed its own rows; the downloaded ones are matched here
		for entry in DownloadManager.shared.downloads where entry.mediaRow.matchesLibrarySearch(self.listKey.search) && seen.insert(entry.id).inserted {
			result.append(entry.mediaRow)
		}

		return result.sorted { self.sort.areInOrder($0, $1) }
	}

	@ViewBuilder
	private func row(_ track: MediaRow) -> some View {
		let isSelecting = self.selection.isActive

		HStack(spacing: 8) {
			if isSelecting {
				SelectionMark(isSelected: self.selection.contains(track.id))
			}

			TrackRow(coverURL: track.coverArt.flatMap { URL(string: $0) }, title: track.title, subtitle: track.artistName, duration: track.duration, fileSize: track.fileSize, onTap: {
				if isSelecting {
					self.selection.toggle(track.id)
				} else {
					PlaybackSource.play(track, recordContext: RecordContext(type: .track, refId: track.id))
				}
			}) {
				if DownloadManager.shared.isDownloaded(trackId: track.id) {
					Image(systemName: "arrow.down.circle.fill")
						.foregroundStyle(DTColor.textPrimary.opacity(0.4))
				}
			}
		}
		// while selecting, a row only ticks: no swipe, no menu
		.swipeActions(edge: .trailing) {
			if !isSelecting {
				Button(role: .destructive) {
					self.pendingDelete = track
				} label: {
					Label(String(localized: "delete"), systemImage: "trash")
				}
				.tint(DTColor.buttonDanger)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
		.swipeActions(edge: .leading) {
			if !isSelecting {
				Button {
					Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [track.id])
				} label: {
					Label(String(localized: "add"), systemImage: "text.badge.plus")
				}
				.tint(DTColor.accentStart)
			}
		}
		// while selecting there is no menu; the tracks may be downloads only, so the queue is the row itself
		.libraryItemMenu(
			item: .track(id: track.id),
			play: { ([track], RecordContext(type: .track, refId: track.id)) },
			isEnabled: !isSelecting,
			onRemoved: { self.paginator?.remove(where: { $0.id == track.id }) }
		)
	}

	private func delete(_ track: MediaRow) {
		guard let server else { return }
		Task {
			do {
				try await server.removeFromLibrary(track)
				self.paginator?.remove(where: { $0.id == track.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
