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
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Library.album(id: self.albumId)) as LibraryAlbumResponse
		} content: { response, _ in
			LibraryAlbumDetailContent(response: response)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct LibraryAlbumDetailContent: View {
	@State private var toast = ToastState()

	let response: LibraryAlbumResponse

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				self.header

				VStack(spacing: 0) {
					ForEach(Array(self.response.tracks.enumerated()), id: \.element.id) { index, track in
						self.trackRow(track)

						if index < self.response.tracks.count - 1 {
							Divider()
								.overlay(DTColor.borderSelect)
						}
					}
				}

				self.footer
			}
			.padding()
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.toast(self.toast)
	}

	@ViewBuilder
	private var header: some View {
		VStack(alignment: .leading, spacing: 10) {
			CoverImage(url: self.response.album.row.coverArt.flatMap { URL(string: $0) })
				.frame(width: 200, height: 200)
				.frame(maxWidth: .infinity)

			Text(self.response.album.row.title)
				.font(DTFont.serif(31))
				.foregroundStyle(DTColor.textPrimary)

			Text(self.response.album.row.artistName)
				.font(DTFont.serif(20))
				.foregroundStyle(DTColor.textPrimary.opacity(0.7))

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
			.padding(.top, 4)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
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
		}
	}

	@ViewBuilder
	private var footer: some View {
		VStack(alignment: .leading, spacing: 4) {
			if let releaseDate = self.response.album.row.releaseDateValue {
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			Text("\(self.response.album.row.trackCount) " + String(localized: "tracks"))
		}
		.font(DTFont.system(16))
		.foregroundStyle(DTColor.textPrimary.opacity(0.5))
	}

	private func play(_ track: MediaRow) {
		PlayerEngine.shared.play(track, queue: self.response.tracks, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}

	private func playAll(shuffle: Bool) {
		guard !self.response.tracks.isEmpty else { return }
		var queue = self.response.tracks
		if shuffle {
			queue.shuffle()
		}
		PlayerEngine.shared.play(queue[0], queue: queue, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}
}
