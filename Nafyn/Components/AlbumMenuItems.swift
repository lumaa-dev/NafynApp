// Made by Lumaa

import SwiftUI
import Safyn

/// The menu items every owned album shares, in the categories of DESIGN.md (divider-separated): add all of it to a
/// playlist, pin, open it; download; remove its downloads, delete. Used by the album card's context menu and the album screen's toolbar menu, so the two
/// always offer the same actions; each place adds its own extras (Play / Shuffle, …) around it.
///
/// Only the album's ID is needed. The owner confirms and performs the two destructive actions.
struct AlbumMenuItems: View {
	@Environment(\.server) private var server: NafynServer?

	let albumId: String

	/// The album's title when the place knows it; otherwise it is fetched together with the tracks on "Download".
	var title: String?

	/// The album's artist (MusicBrainz ID) when the place knows it; otherwise it is fetched on "View Artist".
	var artistId: String?

	/// Called when "Delete downloads" is chosen. `nil` leaves the item out.
	var onDeleteDownloads: (() -> Void)?

	/// Called when "Delete" is chosen. `nil` leaves the item out.
	var onDelete: (() -> Void)?

	var body: some View {
		// Categories, in the order Nafyn's DESIGN.md sets, each ending in a divider: "View" and playlists,
		// modifications, destructive actions. (Playback - Play / Shuffle - is added by the caller, above.)
		Button {
			self.addToPlaylist()
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		PinMenuButton(target: .album(self.albumId))

		// the MusicBrainz version of the album and its artist, not the library's
		Button {
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.send(to: .album(id: self.albumId))
		} label: {
			Label(String(localized: "view-catalog-album"), systemImage: "opticaldisc")
		}
		.tint(Color.primary)

		Button {
			self.openArtist()
		} label: {
			Label(String(localized: "view-artist"), systemImage: "person")
		}
		.tint(Color.primary)

		Divider()

		Button {
			self.download()
		} label: {
			Label(String(localized: "download-album"), systemImage: "arrow.down.circle")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)

		let hasDownloads = self.onDeleteDownloads != nil && !DownloadManager.shared.downloadedTrackIds(albumId: self.albumId).isEmpty

		if hasDownloads || self.onDelete != nil {
			Divider()
		}

		if let onDeleteDownloads = self.onDeleteDownloads, hasDownloads {
			Button(role: .destructive) {
				onDeleteDownloads()
			} label: {
				Label(String(localized: "delete-downloads"), systemImage: "arrow.down.circle.fill")
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

	private func addToPlaylist() {
		let albumId = self.albumId
		let server = self.server
		Task { @MainActor in
			do {
				guard let server else { throw NafynError.unauthenticated }
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: albumId))
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: response.tracks.map(\.id))
			} catch {
				ToastState.app.failure(error)
			}
		}
	}

	private func openArtist() {
		if let artistId = self.artistId {
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.send(to: .artist(id: artistId))
			return
		}

		let albumId = self.albumId
		let server = self.server
		Task { @MainActor in
			do {
				guard let server else { throw NafynError.unauthenticated }
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: albumId))
				guard let artistId = response.album.row.artistMbid else { return }
				PlayerEngine.shared.isExpanded = false
				Navigator.shared.send(to: .artist(id: artistId))
			} catch {
				ToastState.app.failure(error)
			}
		}
	}

	private func download() {
		if let title = self.title {
			DownloadManager.shared.downloadAlbum(id: self.albumId, title: title)
			return
		}

		let albumId = self.albumId
		let server = self.server
		Task { @MainActor in
			do {
				guard let server else { throw NafynError.unauthenticated }
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: albumId))
				DownloadManager.shared.downloadAlbum(id: albumId, title: response.album.row.title)
			} catch {
				ToastState.app.failure(error)
			}
		}
	}
}
