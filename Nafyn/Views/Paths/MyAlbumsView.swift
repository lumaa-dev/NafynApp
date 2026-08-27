// Made by Lumaa

import SwiftUI
import Safyn

struct MyAlbumsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<AlbumRow>? = nil

	private let columns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

	var body: some View {
		ScrollView {
			if let paginator {
				LazyVGrid(columns: self.columns, spacing: 16) {
					ForEach(paginator.items) { album in
						NavigationLink(value: Navigator.Paths.libraryAlbum(id: album.id)) {
							MusicCard(.album(album))
						}
						.buttonStyle(.plain)
						.onAppear { paginator.loadNextPageIfNeeded(currentItem: album) }
					}
				}
				.padding()

				if paginator.isLoadingPage {
					SkeletonMusicGrid(columns: self.columns, count: 2)
						.padding(.horizontal)
				}
			} else {
				SkeletonMusicGrid(columns: self.columns)
					.padding()
			}
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.task {
			guard self.paginator == nil, let server else { return }
			let paginator = Paginator<AlbumRow> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/library/albums", page: page, limit: limit)
			}
			self.paginator = paginator
			await paginator.reset()
		}
		.refreshable {
			await self.paginator?.reset()
		}
		.navigationTitle(String(localized: "albums"))
	}
}
