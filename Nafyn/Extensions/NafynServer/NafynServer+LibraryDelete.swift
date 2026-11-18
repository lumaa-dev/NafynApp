// Made by Lumaa

import Foundation
import Safyn

extension NafynServer {
	/// Removes `track` from the user's library (the file too when nobody else owns it), together with its
	/// download and its place in the local queue. Safyn's `Library.remove(id:)` does the server part.
	@MainActor
	func removeFromLibrary(_ track: MediaRow) async throws {
		try await self.removeFromLibrary(trackId: track.id)
	}

	@MainActor
	func removeFromLibrary(trackId: String) async throws {
		_ = try await self.send(Library.remove(id: trackId)) as RemovedWithFileResponse
		Self.forgetLocally(trackIds: [trackId])
	}

	/// Removes every track the user owns on an album. Safyn has no album-level delete, so this removes the
	/// tracks one by one (concurrently). Returns the removed track IDs.
	@MainActor
	@discardableResult
	func removeLibraryAlbum(id: String) async throws -> [String] {
		let response: LibraryAlbumResponse = try await self.send(Library.album(id: id))
		let ids = response.tracks.map(\.id)
		guard !ids.isEmpty else { throw LibraryDeleteError.notInLibrary }

		try await withThrowingTaskGroup(of: Void.self) { group in
			for trackId in ids {
				group.addTask {
					_ = try await self.send(Library.remove(id: trackId)) as RemovedWithFileResponse
				}
			}
			try await group.waitForAll()
		}

		Self.forgetLocally(trackIds: ids)
		return ids
	}

	/// Drops the downloads and the queue entries of tracks that no longer exist in the library.
	@MainActor
	private static func forgetLocally(trackIds: [String]) {
		DownloadManager.shared.deleteDownloads(trackIds: trackIds)
		SpotlightIndexer.shared.remove(trackIds: trackIds)
		Task { await LibraryCatalog.shared.invalidate() }

		let engine = PlayerEngine.shared
		for index in engine.queue.indices.reversed() where trackIds.contains(engine.queue[index].id) {
			engine.removeFromQueue(at: index)
		}
	}
}

enum LibraryDeleteError: LocalizedError {
	case notInLibrary

	var errorDescription: String? {
		String(localized: "album-not-in-library")
	}
}
