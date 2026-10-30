// Made by Lumaa

import Foundation
import Safyn

/// The user's own library as plain values, for App Intents, Siri and Spotlight, which ask for it without a
/// screen to page through. Only what the user owns: never the catalog.
///
/// Siri gives an intent a few seconds, and fetching a whole library page by page takes longer than that, so
/// a snapshot is kept on disk and answers instantly, even from a cold launch. A snapshot older than
/// ``lifetime`` is still served, and refreshed in the background for the next request. Only the very first
/// request after sign-in (nothing stored yet) waits for the network.
actor LibraryCatalog {
	static let shared = LibraryCatalog()

	/// How long a snapshot counts as current before a background refresh starts.
	private static let lifetime: TimeInterval = 120

	/// Pages fetched at the same time once the first one told how many there are.
	private static let concurrentPages = 4

	private let trackSlot = Slot<MediaRow>(file: "LibraryTracks.json", path: "/api/v1/library/tracks")
	private let albumSlot = Slot<AlbumRow>(file: "LibraryAlbums.json", path: "/api/v1/library/albums")
	private let playlistSlot = Slot<PlaylistRow>(file: "LibraryPlaylists.json", path: "/api/v1/playlist")

	func tracks() async throws -> [MediaRow] {
		do {
			return try await self.rows(self.trackSlot)
		} catch {
			// no route to the server: what is downloaded is still the user's library
			let offline = await MainActor.run { DownloadManager.shared.downloads.map(\.mediaRow) }
			guard !offline.isEmpty else { throw error }
			return offline
		}
	}

	func albums() async throws -> [AlbumRow] {
		try await self.rows(self.albumSlot)
	}

	func playlists() async throws -> [PlaylistRow] {
		try await self.rows(self.playlistSlot)
	}

	/// The owned tracks of one album, in disc and track order.
	func tracks(ofAlbum albumId: String) async throws -> [MediaRow] {
		try await self.tracks()
			.filter { $0.albumId == albumId }
			.sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
	}

	/// Forgets every snapshot (memory and disk), after the library changed or the account did.
	func invalidate() {
		self.trackSlot.clear()
		self.albumSlot.clear()
		self.playlistSlot.clear()
	}

	/// Forgets the playlists only: adding to one doesn't change what the user owns.
	func invalidatePlaylists() {
		self.playlistSlot.clear()
	}

	// MARK: - Snapshots

	/// One kind of row: its snapshot in memory and on disk, and the refresh in flight, if any.
	private final class Slot<Item: Codable & Sendable & Hashable>: @unchecked Sendable {
		let file: String
		let path: String
		var rows: [Item]?
		var date: Date?
		var refreshing: Task<[Item], Error>?
		var generation = 0

		init(file: String, path: String) {
			self.file = file
			self.path = path
		}

		var url: URL {
			FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(self.file)
		}

		func clear() {
			self.generation += 1
			self.rows = nil
			self.date = nil
			self.refreshing?.cancel()
			self.refreshing = nil
			try? FileManager.default.removeItem(at: self.url)
		}
	}

	private func rows<Item>(_ slot: Slot<Item>) async throws -> [Item] {
		if slot.rows == nil, let stored = Self.read(slot) {
			slot.rows = stored.rows
			slot.date = stored.date
		}

		if let rows = slot.rows, let date = slot.date {
			if Date.now.timeIntervalSince(date) >= Self.lifetime {
				_ = self.refresh(slot)
			}
			return rows
		}
		return try await self.refresh(slot).value
	}

	private func refresh<Item>(_ slot: Slot<Item>) -> Task<[Item], Error> {
		if let running = slot.refreshing { return running }

		let generation = slot.generation
		let task = Task { () throws -> [Item] in
			let server = try await AppSession.shared.resolveServer()
			let fetched: [Item] = try await Self.fetchAll(server, path: slot.path)

			// cleared meanwhile (a delete, a sign-out): this answer may already be outdated
			if slot.generation == generation {
				slot.rows = fetched
				slot.date = .now
				Self.write(fetched, to: slot)
			}
			return fetched
		}
		slot.refreshing = task

		Task {
			_ = try? await task.value
			if slot.generation == generation { slot.refreshing = nil }
		}
		return task
	}

	// MARK: - Disk

	private struct Stored<Item: Codable>: Codable {
		var rows: [Item]
		var date: Date
	}

	private static func read<Item>(_ slot: Slot<Item>) -> (rows: [Item], date: Date)? {
		guard let data = try? Data(contentsOf: slot.url),
			  let stored = try? JSONDecoder().decode(Stored<Item>.self, from: data)
		else { return nil }
		return (stored.rows, stored.date)
	}

	private static func write<Item>(_ rows: [Item], to slot: Slot<Item>) {
		guard let data = try? JSONEncoder().encode(Stored(rows: rows, date: .now)) else { return }
		try? data.write(to: slot.url, options: .atomic)
	}

	// MARK: - Network

	/// Page one says how many pages there are; the others are fetched a few at a time.
	private static func fetchAll<Item: Codable & Sendable & Hashable>(_ server: NafynServer, path: String) async throws -> [Item] {
		let limit = 100
		let first: PaginatedResponse<Item> = try await server.fetchPaginated(path: path, page: 1, limit: limit)
		guard first.hasMore else { return first.items }

		let pageSize = max(first.items.count, 1)
		let lastPage = max(2, Int((Double(first.total) / Double(pageSize)).rounded(.up)))

		var pages: [Int: [Item]] = [1: first.items]
		var next = 2

		try await withThrowingTaskGroup(of: (Int, PaginatedResponse<Item>).self) { group in
			func enqueue() {
				guard next <= lastPage else { return }
				let page = next
				next += 1
				group.addTask { (page, try await server.fetchPaginated(path: path, page: page, limit: limit)) }
			}

			for _ in 0..<Self.concurrentPages { enqueue() }
			while let (page, response) = try await group.next() {
				pages[page] = response.items
				enqueue()
			}
		}
		return pages.keys.sorted().flatMap { pages[$0] ?? [] }
	}
}
