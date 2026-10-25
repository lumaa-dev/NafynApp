// Made by Lumaa

import SwiftUI
import Safyn

/// An owned album, fetched via `Library.album(id:)`: only the tracks the requesting user owns, Play/Shuffle
/// instead of Request — distinct from ``AlbumDetailView``, which fetches MusicBrainz metadata for any album.
struct LibraryAlbumDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var albumId: String

	var body: some View {
		AsyncContentView {
			if let server {
				do {
					return try await server.send(Library.album(id: self.albumId)) as LibraryAlbumResponse
				} catch {
					if let offline = Self.offlineResponse(albumId: self.albumId) { return offline }
					throw error
				}
			} else if let offline = Self.offlineResponse(albumId: self.albumId) {
				return offline
			} else {
				throw NafynError.unauthenticated
			}
		} content: { response, _ in
			LibraryAlbumDetailContent(response: response)
		}
		.navigationBarTitleDisplayMode(.inline)
	}

	/// Reconstructs a `LibraryAlbumResponse` from this album's downloaded tracks, so an album the user
	/// downloaded for offline listening still opens when there's no `server` to ask (airplane mode) or
	/// the live fetch fails — mirrors the synthesis `MyAlbumsView` does for its own offline grid entries.
	private static func offlineResponse(albumId: String) -> LibraryAlbumResponse? {
		let tracks = DownloadManager.shared.downloads.filter { $0.albumId == albumId }
		guard let first = tracks.first else { return nil }

		let row = AlbumRow(
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
		let album = LibraryAlbumResponse.Album(row: row, imageColors: [], textColor: "#FFFFFF")
		let mediaRows = tracks.map(\.mediaRow).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		return LibraryAlbumResponse(album: album, tracks: mediaRows)
	}
}

private struct LibraryAlbumDetailContent: View {
	@Environment(\.colorScheme) private var colorScheme

	@State private var toast = ToastState()

	let response: LibraryAlbumResponse

	var body: some View {
		let palette = CoverPalette(imageColors: self.response.album.imageColors, colorScheme: self.colorScheme)

		CoverScrollView(palette: palette) {
			VStack(alignment: .leading, spacing: 16) {
				self.header(palette: palette)

				VStack(alignment: .leading, spacing: 16) {
					HStack {
						Button {
							self.playAll(shuffle: false)
						} label: {
							Label(String(localized: "play"), systemImage: "play.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.filled())

						Button {
							self.playAll(shuffle: true)
						} label: {
							Label(String(localized: "shuffle"), systemImage: "shuffle")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.hollow())
					}

					VStack(spacing: 0) {
						ForEach(Array(self.response.tracks.enumerated()), id: \.element.id) { index, track in
							self.trackRow(track)

							if index < self.response.tracks.count - 1 {
								Divider()
									.overlay(palette.secondary.opacity(0.3))
							}
						}
					}

					self.footer(palette: palette)
				}
				.padding(.horizontal)
				.padding(.bottom)
			}
		}
		.toast(self.toast)
		.scrollEdgeEffectHidden()
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Menu {
					Button {
						DownloadManager.shared.downloadAlbum(id: self.response.album.row.id, title: self.response.album.row.title)
					} label: {
						Label(String(localized: "download-album"), systemImage: "arrow.down.circle")
					}
					.disabled(NetworkMonitor.shared.isOffline)
				} label: {
					Image(systemName: "ellipsis")
				}
				.tint(Color.primary)
			}
		}
	}

	private func header(palette: CoverPalette) -> some View {
		CoverHeader(url: self.response.album.row.coverArt.flatMap { URL(string: $0) }, palette: palette) {
			Text(self.response.album.row.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)

			Text(self.response.album.row.artistName)
				.font(DTFont.serif(20))
				.foregroundStyle(palette.primary)
		}
	}

	@ViewBuilder
	private func trackRow(_ track: MediaRow) -> some View {
		TrackRow(title: track.title, duration: track.duration, fileSize: track.fileSize, verticalPadding: 12, onTap: { self.play(track) })
		.contextMenu {
			Button {
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [track.id])
			} label: {
				Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
			}

			Button {
				Navigator.shared.send(to: .libraryTrack(id: track.id))
			} label: {
				Label(String(localized: "view-track"), systemImage: "info.circle")
			}

			if DownloadManager.shared.isDownloaded(trackId: track.id) {
				Button(role: .destructive) {
					if let entry = DownloadManager.shared.downloads.first(where: { $0.id == track.id }) {
						DownloadManager.shared.delete(entry)
					}
				} label: {
					Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
				}
			} else {
				Button {
					DownloadManager.shared.downloadTrack(track)
				} label: {
					Label(String(localized: "download"), systemImage: "arrow.down.circle")
				}
				.disabled(DownloadManager.shared.isDownloading(trackId: track.id) || NetworkMonitor.shared.isOffline)
			}
		}
	}

	@ViewBuilder
	private func footer(palette: CoverPalette) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			if let releaseDate = self.response.album.row.releaseDateValue {
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			Text("\(self.response.album.row.trackCount) " + String(localized: "tracks"))
		}
		.font(DTFont.system(16))
		.foregroundStyle(palette.secondary)
	}

	private func play(_ track: MediaRow) {
		PlaybackSource.play(track, queue: self.response.tracks, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}

	private func playAll(shuffle: Bool) {
		guard !self.response.tracks.isEmpty else { return }
		var queue = self.response.tracks
		if shuffle {
			queue.shuffle()
		}
		PlaybackSource.play(queue[0], queue: queue, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}
}
