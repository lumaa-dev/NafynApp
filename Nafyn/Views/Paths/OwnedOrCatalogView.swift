// Made by Lumaa

import SwiftUI
import Safyn

/// Opens the library ("owned") version of a track/album when the user has it, and the catalog version
/// (with its Request button) otherwise. Recently-played entries can't know ownership up front, so the
/// check happens here, on arrival.
struct OwnedOrCatalogView<Owned: View, Catalog: View>: View {
	/// `true` when the item is in the user's library.
	let isOwned: () async -> Bool
	@ViewBuilder let owned: () -> Owned
	@ViewBuilder let catalog: () -> Catalog

	@State private var owns: Bool? = nil

	var body: some View {
		Group {
			switch self.owns {
				case .some(true):
					self.owned()
				case .some(false):
					self.catalog()
				case .none:
					SkeletonDetailScreen()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(DTColor.background.ignoresSafeArea())
			}
		}
		.task {
			guard self.owns == nil else { return }
			self.owns = await self.isOwned()
		}
	}
}

/// Recently-played track → library track (by Nafyn media ID) if owned, else the MusicBrainz track page.
struct RecentTrackView: View {
	@Environment(\.server) private var server: NafynServer?

	let mediaId: String
	let mbid: String

	var body: some View {
		OwnedOrCatalogView {
			guard let server else { return DownloadManager.shared.isDownloaded(trackId: self.mediaId) }
			do {
				_ = try await server.send(Library.track(id: self.mediaId)) as MediaRow
				return true
			} catch let error as NafynError {
				// unreachable server: the library view can still serve a downloaded copy
				if case .transport = error { return DownloadManager.shared.isDownloaded(trackId: self.mediaId) }
				return false
			} catch {
				return false
			}
		} owned: {
			LibraryTrackDetailView(trackId: self.mediaId)
		} catalog: {
			TrackDetailView(trackId: self.mbid)
		}
	}
}

/// Recently-played album → library album if the user owns any track of it, else the MusicBrainz album page.
struct RecentAlbumView: View {
	@Environment(\.server) private var server: NafynServer?

	let albumId: String

	var body: some View {
		OwnedOrCatalogView {
			guard let server else { return DownloadManager.shared.downloads.contains { $0.albumId == self.albumId } }
			do {
				let response = try await server.send(Library.album(id: self.albumId)) as LibraryAlbumResponse
				return !response.tracks.isEmpty
			} catch let error as NafynError {
				if case .transport = error { return DownloadManager.shared.downloads.contains { $0.albumId == self.albumId } }
				return false
			} catch {
				return false
			}
		} owned: {
			LibraryAlbumDetailView(albumId: self.albumId)
		} catalog: {
			AlbumDetailView(albumId: self.albumId)
		}
	}
}
