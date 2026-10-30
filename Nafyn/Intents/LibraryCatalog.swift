// Made by Lumaa

import Foundation
import Safyn

/// The user's own library as plain values, for App Intents, Siri and Spotlight, which ask for it without a
/// screen to page through. Fetched whole (page by page) and kept briefly so one Siri request or shortcut run
/// doesn't download it again for every entity it resolves. Only what the user owns: never the catalog.
actor LibraryCatalog {
	static let shared = LibraryCatalog()

	private static let lifetime: TimeInterval = 120

	private var tracksCache: (rows: [MediaRow], date: Date)?
	private var albumsCache: (rows: [AlbumRow], date: Date)?
	private var playlistsCache: (rows: [PlaylistRow], date: Date)?

	func tracks() async throws -> [MediaRow] {
		if let cache = self.tracksCache, Date.now.timeIntervalSince(cache.date) < Self.lifetime { return cache.rows }

		let rows: [MediaRow]
		do {
			let server = try await AppSession.shared.resolveServer()
			rows = try await Self.fetchAll(server, path: "/api/v1/library/tracks")
		} catch {
			// no route to the server: what is downloaded is still the user's library
			let offline = await MainActor.run { DownloadManager.shared.downloads.map(\.mediaRow) }
			guard !offline.isEmpty else { throw error }
			return offline
		}
		self.tracksCache = (rows, .now)
		return rows
	}

	func albums() async throws -> [AlbumRow] {
		if let cache = self.albumsCache, Date.now.timeIntervalSince(cache.date) < Self.lifetime { return cache.rows }

		let server = try await AppSession.shared.resolveServer()
		let rows: [AlbumRow] = try await Self.fetchAll(server, path: "/api/v1/library/albums")
		self.albumsCache = (rows, .now)
		return rows
	}

	func playlists() async throws -> [PlaylistRow] {
		if let cache = self.playlistsCache, Date.now.timeIntervalSince(cache.date) < Self.lifetime { return cache.rows }

		let server = try await AppSession.shared.resolveServer()
		let rows: [PlaylistRow] = try await Self.fetchAll(server, path: "/api/v1/playlist")
		self.playlistsCache = (rows, .now)
		return rows
	}

	/// The owned tracks of one album, in disc and track order.
	func tracks(ofAlbum albumId: String) async throws -> [MediaRow] {
		try await self.tracks()
			.filter { $0.albumId == albumId }
			.sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
	}

	/// Forgets the snapshot, after the library or a playlist changed.
	func invalidate() {
		self.tracksCache = nil
		self.albumsCache = nil
		self.playlistsCache = nil
	}

	private static func fetchAll<Item: Codable & Sendable & Hashable>(_ server: NafynServer, path: String) async throws -> [Item] {
		var items: [Item] = []
		var page = 1
		while true {
			let response: PaginatedResponse<Item> = try await server.fetchPaginated(path: path, page: page, limit: 100)
			items.append(contentsOf: response.items)
			guard response.hasMore else { break }
			page += 1
		}
		return items
	}
}
