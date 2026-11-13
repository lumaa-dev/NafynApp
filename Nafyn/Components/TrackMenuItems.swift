// Made by Lumaa

import SwiftUI
import Safyn

/// The context menu items every owned track shares, in the categories of DESIGN.md (divider-separated): add to a
/// playlist, pin, open it; change its album, download; remove the download, delete from the library. Used by library track rows, cards, charts and the mini player; each
/// place adds its own extras (Play / Shuffle, …) around it.
///
/// Only the track's ID is needed: places that know just that (a recently played card, a chart row) pass
/// `trackId`, and the full row is fetched only if the user picks "Download".
struct TrackMenuItems: View {
	@Environment(\.server) private var server: NafynServer?

	let trackId: String
	var track: MediaRow?

	/// Offer "View track". Off where the menu already sits on that track's own screen.
	var showsViewTrack = true

	/// Called when "Delete" is chosen; the owner confirms and removes. `nil` leaves the item out.
	var onDelete: (() -> Void)?

	/// Title + artist for "Open on YouTube" / "Share", when only the ID is known (taken from `track` otherwise).
	var share: ExternalShareItem?

	init(track: MediaRow, showsViewTrack: Bool = true, onDelete: (() -> Void)? = nil) {
		self.trackId = track.id
		self.track = track
		self.showsViewTrack = showsViewTrack
		self.onDelete = onDelete
		self.share = ExternalShareItem(title: track.title, artist: track.artistName)
	}

	init(trackId: String, share: ExternalShareItem? = nil, showsViewTrack: Bool = true, onDelete: (() -> Void)? = nil) {
		self.trackId = trackId
		self.track = nil
		self.showsViewTrack = showsViewTrack
		self.onDelete = onDelete
		self.share = share
	}

	var body: some View {
		// Categories, in the order Nafyn's DESIGN.md sets, each ending in a divider: "View" and playlists,
		// modifications, destructive actions. (Playback - Play / Shuffle - is added by the caller, above.)
		Button {
			Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [self.trackId])
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		PinMenuButton(target: .track(self.trackId))

		// the MusicBrainz versions of the track's album and artist, not the library's
		if self.track.map({ !$0.albumId.isEmpty }) ?? true {
			Button {
				self.openCatalogAlbum()
			} label: {
				Label(String(localized: "view-catalog-album"), systemImage: "opticaldisc")
			}
			.tint(Color.primary)
		}

		if self.track.map({ $0.artistMbid != nil }) ?? true {
			Button {
				self.openArtist()
			} label: {
				Label(String(localized: "view-artist"), systemImage: "person")
			}
			.tint(Color.primary)
		}

		if self.showsViewTrack {
			Button {
				// the full player is a cover over the tabs; close it so the pushed screen is visible
				PlayerEngine.shared.isExpanded = false
				Navigator.shared.send(to: .libraryTrack(id: self.trackId))
			} label: {
				Label(String(localized: "view-track"), systemImage: "info.circle")
			}
			.tint(Color.primary)
		}

		if let share = self.share {
			ExternalLinkMenuItems(item: share)
		}

		Divider()

		Button {
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.sheet = Navigator.Paths.editMetadata(trackIds: [self.trackId])
		} label: {
			Label(String(localized: "edit-metadata"), systemImage: "pencil")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)

		Button {
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.sheet = Navigator.Paths.changeAlbum(trackId: self.trackId)
		} label: {
			Label(String(localized: "change-album"), systemImage: "square.stack")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)

		if !DownloadManager.shared.isDownloaded(trackId: self.trackId) {
			Button {
				self.download()
			} label: {
				Label(String(localized: "download"), systemImage: "arrow.down.circle")
			}
			.tint(Color.primary)
			.disabled(DownloadManager.shared.isDownloading(trackId: self.trackId) || NetworkMonitor.shared.isOffline)
		}

		if DownloadManager.shared.isDownloaded(trackId: self.trackId) || self.onDelete != nil {
			Divider()
		}

		if DownloadManager.shared.isDownloaded(trackId: self.trackId) {
			Button(role: .destructive) {
				DownloadManager.shared.deleteDownloads(trackIds: [self.trackId])
			} label: {
				Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
			}
			.tint(DTColor.dangerText)
		}

		if let onDelete = self.onDelete {
			Button(role: .destructive) {
				onDelete()
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.dangerText)
			.disabled(NetworkMonitor.shared.isOffline)
		}
	}

	/// The row, from the one already known or else fetched.
	private func resolvedTrack() async -> MediaRow? {
		if let track = self.track { return track }
		guard let server else { return nil }
		return (try? await server.send(Library.track(id: self.trackId)) as LibraryTrackResponse)?.row
	}

	private func openCatalogAlbum() {
		Task { @MainActor in
			guard let albumId = await self.resolvedTrack()?.albumId, !albumId.isEmpty else { return }
			// the full player is a cover over the tabs; close it so the pushed screen is visible
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.send(to: .album(id: albumId))
		}
	}

	private func openArtist() {
		Task { @MainActor in
			guard let artistId = await self.resolvedTrack()?.artistMbid else { return }
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.send(to: .artist(id: artistId))
		}
	}

	private func download() {
		if let track = self.track {
			DownloadManager.shared.downloadTrack(track)
			return
		}

		let trackId = self.trackId
		let server = self.server
		Task { @MainActor in
			guard let server, let response = try? await server.send(Library.track(id: trackId)) as LibraryTrackResponse else { return }
			DownloadManager.shared.downloadTrack(response.row)
		}
	}
}
