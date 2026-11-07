// Made by Lumaa

import SwiftUI
import Safyn

struct MyPlaylistsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<PlaylistRow>? = nil
	@State private var showCreate = false
	@State private var toast = ToastState()
	@State private var selection = BulkSelection()
	@State private var isConfirmingBulkDelete = false

	/// The signed-in user's ID: only their own playlists can be deleted.
	@State private var myId: String? = nil

	var body: some View {
		ScrollView {
			if let paginator {
				FoldGrid(spacing: 16) {
					ForEach(paginator.items) { playlist in
						self.card(playlist)
							.onAppear { paginator.loadNextPageIfNeeded(currentItem: playlist) }
					}
				}
				.padding()

				if paginator.isLoadingPage {
					SkeletonMusicGrid(count: 2)
						.padding(.horizontal)
				}
			} else {
				SkeletonMusicGrid()
					.padding()
			}
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn(maxWidth: DTLayout.gridWidth)
		.background(DTColor.background.ignoresSafeArea())
		.task {
			guard self.paginator == nil, let server else { return }
			let paginator = Paginator<PlaylistRow> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/playlist", page: page, limit: limit)
			}
			self.paginator = paginator
			await paginator.reset()
		}
		.task {
			guard self.myId == nil, let server else { return }
			self.myId = (try? await server.send(User.me) as NafynUser)?.id
		}
		.refreshable {
			await self.paginator?.reset()
		}
		.navigationTitle(String(localized: "playlists"))
		.bulkSelectionSubtitle(self.selection)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					self.showCreate = true
				} label: {
					Label(String(localized: "new-playlist"), systemImage: "plus")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
				.disabled(self.selection.isActive)
			}

			// creating and selecting have nothing to do with one another
			ToolbarSpacer(.fixed, placement: .primaryAction)
		}
		.bulkSelectionToolbar(self.selection, allIds: self.paginator?.items.map(\.id) ?? []) {
			self.bulkActions
		}
		.toast(self.toast)
		.alert(
			String(localized: "delete-playlists-confirm \(self.deletablePlaylists.count)"),
			isPresented: self.$isConfirmingBulkDelete
		) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.bulkDelete()
			}
		}
		.sheet(isPresented: self.$showCreate) {
			CreatePlaylistSheet { newPlaylist in
				self.paginator?.prepend(newPlaylist)
			}
		}
	}

	/// One playlist: opens it, or ticks it while selecting.
	@ViewBuilder
	private func card(_ playlist: PlaylistRow) -> some View {
		if self.selection.isActive {
			// a plain button instead of the link: the tap ticks the card
			Button {
				self.selection.toggle(playlist.id)
			} label: {
				MusicCard(.playlist(playlist))
					.overlay(alignment: .topLeading) {
						SelectionMark(isSelected: self.selection.contains(playlist.id))
							.padding(6)
					}
					.opacity(self.selection.contains(playlist.id) ? 1 : 0.7)
			}
			.buttonStyle(.plain)
		} else {
			NavigationLink(value: Navigator.Paths.playlist(id: playlist.id)) {
				MusicCard(.playlist(playlist))
			}
			.buttonStyle(.plain)
		}
	}

	/// The ticked playlists, as listed.
	private var selectedPlaylists: [PlaylistRow] {
		(self.paginator?.items ?? []).filter { self.selection.contains($0.id) }
	}

	/// The ticked playlists the user owns, the only ones they can delete.
	private var deletablePlaylists: [PlaylistRow] {
		self.selectedPlaylists.filter { $0.ownerId == self.myId }
	}

	@ViewBuilder
	private var bulkActions: some View {
		let playlists = self.selectedPlaylists

		BulkPinButton(targets: playlists.map { .playlist($0.id) }, toast: self.toast) {
			self.selection.end()
		}

		Button {
			for playlist in playlists {
				DownloadManager.shared.downloadPlaylist(id: playlist.id, title: playlist.title)
			}
			self.selection.end()
		} label: {
			Label(String(localized: "download"), systemImage: "arrow.down.circle")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)

		Button(role: .destructive) {
			self.isConfirmingBulkDelete = true
		} label: {
			Label(String(localized: "delete"), systemImage: "trash")
		}
		.tint(DTColor.dangerText)
		.disabled(NetworkMonitor.shared.isOffline || self.deletablePlaylists.isEmpty)
	}

	private func bulkDelete() {
		guard let server else { return }
		let ids = self.deletablePlaylists.map(\.id)
		Task { @MainActor in
			let result = await BulkActions.deletePlaylists(ids, server: server)
			self.paginator?.remove(where: { result.succeeded.contains($0.id) })
			if let error = result.error {
				self.toast.failure(error)
			}
			await PinStore.shared.refresh(server: server)
			self.selection.end()
		}
	}
}
