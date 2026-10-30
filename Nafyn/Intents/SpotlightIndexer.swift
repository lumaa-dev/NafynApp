// Made by Lumaa

import AppIntents
import CoreSpotlight
import Foundation
import Safyn

/// Keeps the user's library in Spotlight: every owned track and album is donated as an app entity (see
/// `SongEntity`/`AlbumEntity`), so it shows up in system search, in Siri's and Apple Intelligence's view of the
/// app, and opens through `OpenSongIntent`/`OpenAlbumIntent`.
///
/// The index is a named one (`NafynLibrary`), never the default. A sync indexes what the library holds now and
/// deletes what it held at the last sync and no longer does, so deleting music in the app, or on another
/// device, takes it out of Spotlight too.
@MainActor
final class SpotlightIndexer {
	static let shared = SpotlightIndexer()
	nonisolated static let indexName = "NafynLibrary"

	/// Entities per `indexAppEntities` call: big enough to be quick, small enough to stay responsive.
	private static let batchSize = 250

	/// A sync that ran this recently is not repeated unless asked for (`syncNow`).
	private static let minimumInterval: TimeInterval = 15 * 60

	private var pending: Task<Void, Never>?
	private var isSyncing = false
	private var lastSync: Date?

	private init() {}

	/// Syncs shortly after sign-in or launch, off the critical path.
	func scheduleSync() {
		if let lastSync, Date.now.timeIntervalSince(lastSync) < Self.minimumInterval { return }

		self.pending?.cancel()
		self.pending = Task {
			try? await Task.sleep(for: .seconds(3))
			guard !Task.isCancelled else { return }
			await self.syncNow()
		}
	}

	/// Indexes the whole library and forgets what was removed since the last sync.
	func syncNow() async {
		guard !self.isSyncing, AppSession.shared.server != nil else { return }
		self.isSyncing = true
		defer { self.isSyncing = false }

		await LibraryCatalog.shared.invalidate()

		do {
			let tracks = try await LibraryCatalog.shared.tracks()
			let albums = try await LibraryCatalog.shared.albums()
			let index = CSSearchableIndex(name: Self.indexName)

			let songs = tracks.map(SongEntity.init(row:))
			for batch in songs.chunked(into: Self.batchSize) {
				try await index.indexAppEntities(batch)
			}
			let albumEntities = albums.map(AlbumEntity.init(row:))
			for batch in albumEntities.chunked(into: Self.batchSize) {
				try await index.indexAppEntities(batch)
			}

			var known = Self.loadKnown()
			let staleSongs = known.songs.subtracting(tracks.map(\.id))
			let staleAlbums = known.albums.subtracting(albums.map(\.id))
			if !staleSongs.isEmpty {
				try await index.deleteAppEntities(identifiedBy: Array(staleSongs), ofType: SongEntity.self)
			}
			if !staleAlbums.isEmpty {
				try await index.deleteAppEntities(identifiedBy: Array(staleAlbums), ofType: AlbumEntity.self)
			}

			known.songs = Set(tracks.map(\.id))
			known.albums = Set(albums.map(\.id))
			Self.save(known)
			self.lastSync = .now

			// the phrases Siri offers ("Play …") are built from the library's suggested entities
			NafynShortcuts.updateAppShortcutParameters()
		} catch {
			// offline or signed out: the next launch syncs again
		}
	}

	/// Takes deleted tracks (and the albums that lost their last track) out of Spotlight right away.
	func remove(trackIds: [String], albumIds: [String] = []) {
		guard !trackIds.isEmpty || !albumIds.isEmpty else { return }

		Task {
			let index = CSSearchableIndex(name: Self.indexName)
			if !trackIds.isEmpty {
				try? await index.deleteAppEntities(identifiedBy: trackIds, ofType: SongEntity.self)
			}
			if !albumIds.isEmpty {
				try? await index.deleteAppEntities(identifiedBy: albumIds, ofType: AlbumEntity.self)
			}

			var known = Self.loadKnown()
			known.songs.subtract(trackIds)
			known.albums.subtract(albumIds)
			Self.save(known)
		}
	}

	/// Signed out or switched account: nothing of the previous library may stay searchable.
	func reset() {
		self.pending?.cancel()
		self.lastSync = nil

		Task {
			let index = CSSearchableIndex(name: Self.indexName)
			try? await index.deleteAppEntities(ofType: SongEntity.self)
			try? await index.deleteAppEntities(ofType: AlbumEntity.self)
			Self.save(Known())
		}
	}

	// MARK: - What was indexed

	private struct Known: Codable {
		var songs: Set<String> = []
		var albums: Set<String> = []
	}

	private static var knownURL: URL {
		let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		return directory.appendingPathComponent("SpotlightIndexedIDs.json")
	}

	private static func loadKnown() -> Known {
		guard let data = try? Data(contentsOf: self.knownURL), let known = try? JSONDecoder().decode(Known.self, from: data) else { return Known() }
		return known
	}

	private static func save(_ known: Known) {
		try? JSONEncoder().encode(known).write(to: self.knownURL, options: .atomic)
	}
}

private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		stride(from: 0, to: self.count, by: size).map { Array(self[$0..<Swift.min($0 + size, self.count)]) }
	}
}
