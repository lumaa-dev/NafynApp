// Made by Lumaa

import SwiftUI
import Safyn

struct MyPlaylistsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<PlaylistRow>? = nil
	@State private var showCreate = false

	private let columns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

	var body: some View {
		ScrollView {
			if let paginator {
				LazyVGrid(columns: self.columns, spacing: 16) {
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
					ProgressView()
						.padding()
				}
			} else {
				ProgressView()
					.padding()
			}
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
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
					Image(systemName: "plus")
				}
			}
		}
		.sheet(isPresented: self.$showCreate) {
			CreatePlaylistSheet { newPlaylist in
				self.paginator?.prepend(newPlaylist)
			}
		}
	}
}
