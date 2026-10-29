// Made by Lumaa

import SwiftUI
import Safyn

/// The context menu items every owned track shares: add to a playlist, open it, download or remove the
/// download, delete from the library. Used by library track rows and the mini player; each place adds its
/// own extras (Play / Shuffle, …) around it.
struct TrackMenuItems: View {
	let track: MediaRow

	/// Offer "View track". Off where the menu already sits on that track's own screen.
	var showsViewTrack = true

	/// Called when "Delete" is chosen; the owner confirms and removes. `nil` leaves the item out.
	var onDelete: (() -> Void)?

	var body: some View {
		Button {
			Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [self.track.id])
		} label: {
			Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
		}
		.tint(Color.primary)

		if self.showsViewTrack {
			Button {
				// the full player is a cover over the tabs; close it so the pushed screen is visible
				PlayerEngine.shared.isExpanded = false
				Navigator.shared.send(to: .libraryTrack(id: self.track.id))
			} label: {
				Label(String(localized: "view-track"), systemImage: "info.circle")
			}
			.tint(Color.primary)
		}

		if DownloadManager.shared.isDownloaded(trackId: self.track.id) {
			Button(role: .destructive) {
				DownloadManager.shared.deleteDownloads(trackIds: [self.track.id])
			} label: {
				Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
			}
			.tint(DTColor.buttonDanger)
		} else {
			Button {
				DownloadManager.shared.downloadTrack(self.track)
			} label: {
				Label(String(localized: "download"), systemImage: "arrow.down.circle")
			}
			.tint(Color.primary)
			.disabled(DownloadManager.shared.isDownloading(trackId: self.track.id) || NetworkMonitor.shared.isOffline)
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
}
