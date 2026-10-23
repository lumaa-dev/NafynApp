// Made by Lumaa

import SwiftUI
import Safyn

struct MyPlaylistsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<PlaylistRow>? = nil
	@State private var showCreate = false

	var body: some View {
		ScrollView {
			if let paginator {
				FoldGrid(spacing: 16) {
					ForEach(paginator.items) { playlist in
						NavigationLink(value: Navigator.Paths.playlist(id: playlist.id)) {
							MusicCard(.playlist(playlist))
						}
						.buttonStyle(.plain)
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
		.refreshable {
			await self.paginator?.reset()
		}
		.navigationTitle(String(localized: "playlists"))
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					self.showCreate = true
				} label: {
					Label(String(localized: "new-playlist"), systemImage: "plus")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
			}
		}
		.sheet(isPresented: self.$showCreate) {
			CreatePlaylistSheet { newPlaylist in
				self.paginator?.prepend(newPlaylist)
			}
		}
	}
}
