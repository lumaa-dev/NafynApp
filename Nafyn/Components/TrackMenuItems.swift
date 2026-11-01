// Made by Lumaa

import SwiftUI
import Safyn

/// The context menu items every owned track shares: add to a playlist, pin, open it, download or remove the
/// download, delete from the library. Used by library track rows, cards, charts and the mini player; each
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

	init(track: MediaRow, showsViewTrack: Bool = true, onDelete: (() -> Void)? = nil) {
		self.trackId = track.id
		self.track = track
		self.showsViewTrack = showsViewTrack
		self.onDelete = onDelete
	}

	init(trackId: String, showsViewTrack: Bool = true, onDelete: (() -> Void)? = nil) {
		self.trackId = trackId
		self.track = nil
		self.showsViewTrack = showsViewTrack
		self.onDelete = onDelete
	}

	var body: some View {
		Button {
			Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [self.trackId])
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		PinMenuButton(target: .track(self.trackId))

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

		if DownloadManager.shared.isDownloaded(trackId: self.trackId) {
			Button(role: .destructive) {
				DownloadManager.shared.deleteDownloads(trackIds: [self.trackId])
			} label: {
				Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
			}
			.tint(DTColor.buttonDanger)
		} else {
			Button {
				self.download()
			} label: {
				Label(String(localized: "download"), systemImage: "arrow.down.circle")
			}
			.tint(Color.primary)
			.disabled(DownloadManager.shared.isDownloading(trackId: self.trackId) || NetworkMonitor.shared.isOffline)
		}

		if let onDelete = self.onDelete {
			Button(role: .destructive) {
				onDelete()
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
			.disabled(NetworkMonitor.shared.isOffline)
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
