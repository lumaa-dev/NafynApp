// Made by Lumaa

import SwiftUI
import Safyn

struct MyAlbumsView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<AlbumRow>? = nil

	var body: some View {
		ScrollView {
			if let paginator {
				FoldGrid(spacing: 16) {
					ForEach(self.mergedAlbums) { album in
						NavigationLink(value: Navigator.Paths.libraryAlbum(id: album.id)) {
							MusicCard(.album(album))
								.overlay(alignment: .topTrailing) {
									if DownloadManager.shared.downloads.contains(where: { $0.albumId == album.id }) {
										Image(systemName: "arrow.down.circle.fill")
											.foregroundStyle(DTColor.textPrimary)
											.padding(6)
											.background(Circle().fill(DTColor.surfaceSelect))
											.padding(6)
									}
								}
						}
						.buttonStyle(.plain)
						.onAppear { paginator.loadNextPageIfNeeded(currentItem: album) }
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
			result.append(AlbumRow(
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
			))
		}

		return result.sorted { $0.addedAtDate > $1.addedAtDate }
	}
}
