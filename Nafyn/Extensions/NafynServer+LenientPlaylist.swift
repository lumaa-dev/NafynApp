// Made by Lumaa

import Foundation
import Safyn

/// See ``LenientUser`` (in `NafynServer+LenientDecoding.swift`) for why a playlist's `owner`/`members`/
/// `addedBy` need lenient decoding at all — this file only adds the playlist-specific mirrors on top.
private struct LenientPlaylistEntry: Decodable {
	let entryId: String
	let addedBy: LenientUser
	let position: Double
	let addedAt: Int64
	let media: MediaRow

	var resolved: PlaylistEntry {
		PlaylistEntry(entryId: entryId, addedBy: addedBy.resolved, position: position, addedAt: addedAt, media: media)
	}
}

private struct LenientPlaylistDetail: Decodable {
	let playlist: PlaylistRow
	let owner: LenientUser
	let members: [LenientUser]
	let entries: [LenientPlaylistEntry]
	let entriesTotal: Int
	let entriesHasMore: Bool
	let viewer: PlaylistDetail.Viewer

	var resolved: PlaylistDetail {
		PlaylistDetail(playlist: playlist, owner: owner.resolved, members: members.map { $0.resolved }, entries: entries.map { $0.resolved }, entriesTotal: entriesTotal, entriesHasMore: entriesHasMore, viewer: viewer)
	}
}

extension NafynServer {
	/// `Playlist.get(pid:)`, tolerant of the server's compact user projection for `owner`/`members`.
	func fetchPlaylistDetail(pid: String) async throws -> PlaylistDetail {
		let data = try await self.sendRaw(Playlist.get(pid: pid))
		do {
			return try JSONDecoder().decode(LenientPlaylistDetail.self, from: data).resolved
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}

	/// `Playlist.tracks(pid:page:limit:)`, tolerant of the compact `addedBy` projection AND using
	/// `?page=` instead of Safyn's broken `?offset=` query (see `NafynServer+PagedFetch.swift`).
	func fetchPlaylistTracks(pid: String, page: Int, limit: Int) async throws -> PaginatedResponse<PlaylistEntry> {
		let data = try await self.fetchGET(path: "/api/v1/playlist/\(pid)/tracks", queryItems: [
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "limit", value: String(limit)),
		])

		do {
			let envelope = try JSONDecoder().decode(RawPaginatedEnvelope<LenientPlaylistEntry>.self, from: data)
			return PaginatedResponse(items: envelope.items.map { $0.resolved }, page: envelope.page, limit: envelope.limit, total: envelope.total, hasMore: envelope.hasMore)
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}
}
