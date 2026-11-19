// Made by Lumaa

import SwiftUI
import Safyn

/// An owned album, fetched via `Library.album(id:)`: only the tracks the requesting user owns, Play/Shuffle
/// instead of Request — distinct from ``AlbumDetailView``, which fetches MusicBrainz metadata for any album.
struct LibraryAlbumDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var albumId: String

	var body: some View {
		AsyncContentView(placeholder: LibraryAlbumResponse.placeholder) {
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
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.dismiss) private var dismiss

	@State private var toast = ToastState()
	@State private var pendingDelete: MediaRow? = nil
	@State private var showDeleteDownloadsConfirm = false
	@State private var showDeleteAlbumConfirm = false

	/// Tracks deleted from this screen, hidden right away instead of re-fetching the album.
	@State private var removedTrackIds: Set<String> = []

	let response: LibraryAlbumResponse

	/// The owned tracks still on the album.
	private var tracks: [MediaRow] {
		self.response.tracks.filter { !self.removedTrackIds.contains($0.id) }
	}

	private var downloadedTrackIds: [String] {
		DownloadManager.shared.downloadedTrackIds(albumId: self.response.album.row.id)
	}

	var body: some View {
		let palette = CoverPalette(imageColors: self.response.album.imageColors, colorScheme: self.colorScheme)

		// Regular width (Duo inner display, iPad) or a phone held sideways: cover and details in one pane,
		// Play/Shuffle and the track list in the other.
		AdaptiveCoverDetail(palette: palette) {
			self.header(palette: palette)
		} compact: {
			self.actions
			self.trackList(palette: palette)
			self.footer(palette: palette)
		} primary: {
			self.footer(palette: palette)
		} secondary: {
			self.actions
			self.trackList(palette: palette)
		}
		.toast(self.toast)
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
		.alert(String(localized: "delete-downloads-confirm"), isPresented: self.$showDeleteDownloadsConfirm) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				DownloadManager.shared.deleteDownloads(trackIds: self.downloadedTrackIds)
			}
		}
		.alert(String(localized: "delete-album-confirm"), isPresented: self.$showDeleteAlbumConfirm) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.deleteAlbum()
			}
		}
		.toolbar {
			MediaVersionPicker(current: .library, counterpart: self.response.album.row.id.isMusicBrainzId ? .album(id: self.response.album.row.id) : nil) { path in
				switch path {
					case .libraryAlbum(let id), .recentAlbum(let id): id == self.response.album.row.id
					default: false
				}
			}

			ToolbarOverflowMenu {
				// the same items as the album's card in a grid, plus Play / Shuffle which a card's menu leads with
				ControlGroup {
					Button {
						self.playAll(shuffle: false)
					} label: {
						Label(String(localized: "play"), systemImage: "play.fill")
					}
					.tint(Color.primary)

					Button {
						self.playAll(shuffle: true)
					} label: {
						Label(String(localized: "shuffle"), systemImage: "shuffle")
					}
					.tint(Color.primary)
				}

				Divider()

				AlbumMenuItems(albumId: self.response.album.row.id, title: self.response.album.row.title, artistId: self.response.album.row.artistMbid, artistName: self.response.album.row.artistName, onDeleteDownloads: {
					self.showDeleteDownloadsConfirm = true
				}, onDelete: {
					self.showDeleteAlbumConfirm = true
				})
			}
		}
	}

	private func header(palette: CoverPalette) -> some View {
		CoverHeader(url: self.response.album.row.coverURL(size: 1000), palette: palette) {
			Text(self.response.album.row.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)

			Text(self.response.album.row.artistName)
				.font(DTFont.serif(20))
				.foregroundStyle(palette.primary)
		}
	}

	/// Play and shuffle the whole album.
	@ViewBuilder
	private var actions: some View {
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
	}

	@ViewBuilder
	private func trackList(palette: CoverPalette) -> some View {
		let groups = self.discGroups

		VStack(spacing: 0) {
			ForEach(groups, id: \.number) { group in
				// disc headers only when the album actually spans several discs
				if groups.count > 1 {
					DiscHeader(number: group.number, title: group.title, isFirst: group.number == groups.first?.number, palette: palette)
				}

				ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
					self.trackRow(track)

					if index < group.tracks.count - 1 {
						Divider()
							.overlay(palette.secondary.opacity(0.3))
					}
				}
			}
		}
	}

	/// The owned tracks per disc, in the server's order; a track without a disc number sits on disc 1.
	private var discGroups: [(number: Double, title: String?, tracks: [MediaRow])] {
		let byDisc = Dictionary(grouping: self.tracks, by: { $0.discNumber ?? 1 })
		return byDisc.keys.sorted().map { number in
			let title = self.response.discs?.first { $0.number == number }?.title
			return (number, title?.isEmpty == false ? title : nil, byDisc[number] ?? [])
		}
	}

	@ViewBuilder
	private func trackRow(_ track: MediaRow) -> some View {
		TrackRow(title: track.title, duration: track.duration, fileSize: track.fileSize, verticalPadding: 12, onTap: { self.play(track) })
		.contextMenu {
			TrackMenuItems(track: track) {
				self.pendingDelete = track
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

	private func deleteAlbum() {
		guard let server else { return }
		Task {
			do {
				try await server.removeLibraryAlbum(id: self.response.album.row.id)
				await PinStore.shared.refresh(server: server)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func delete(_ track: MediaRow) {
		guard let server else { return }
		Task {
			do {
				try await server.removeFromLibrary(track)
				self.removedTrackIds.insert(track.id)
				// nothing left to show: the album is gone from the library
				if self.tracks.isEmpty {
					self.dismiss()
				}
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func play(_ track: MediaRow) {
		PlaybackSource.play(track, queue: self.tracks, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}

	private func playAll(shuffle: Bool) {
		guard !self.tracks.isEmpty else { return }
		var queue = self.tracks
		if shuffle {
			queue.shuffle()
		}
		PlaybackSource.play(queue[0], queue: queue, recordContext: RecordContext(type: .album, refId: self.response.album.row.id))
	}
}
