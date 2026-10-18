// Made by Lumaa

import Foundation
import Safyn

/// `Request.all`'s `requestedBy` is resolved server-side via a compact user projection (confirmed
/// against `requests.ts`'s `rowToRequest`, which calls `getUserById(id, compact: true)`) — an object
/// missing `permissions`/`lastFm`/`discogs`. `UserRef.init(from:)` tries to decode that object as a full
/// `NafynUser` (fails, missing `permissions`), then falls back to decoding it as a plain `String` — which
/// also fails since it's an object, not a string — so the fallback itself throws, failing the entire
/// `NafynRequest`/list decode. This is why the Requests tab shows nothing at all rather than erroring
/// visibly: `Paginator` catches the error into `error`, which `PaginatedList` doesn't currently surface.
private struct LenientNafynRequest: Decodable {
	let id: String
	let musicbrainzId: String
	let info: MediaInfo?
	let type: RequestKind
	let status: String
	let requestedBy: LenientUserRef
	let createdAt: Date
	let updatedAt: Date

	var resolved: NafynRequest {
		NafynRequest(id: id, musicbrainzId: musicbrainzId, info: info, type: type, status: RequestStatus(rawValue: self.status) ?? .waiting, requestedBy: requestedBy.resolved, createdAt: createdAt, updatedAt: updatedAt)
	}
}

extension NafynServer {
	/// `Request.all(page:limit:)`, tolerant of the compact `requestedBy` projection AND using `?page=`
	/// instead of Safyn's broken `?offset=` query (see `NafynServer+PagedFetch.swift`).
	func fetchRequests(page: Int, limit: Int) async throws -> PaginatedResponse<NafynRequest> {
		let data = try await self.fetchGET(path: "/api/v1/requests", queryItems: [
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "limit", value: String(limit)),
		])

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			let envelope = try decoder.decode(RawPaginatedEnvelope<LenientNafynRequest>.self, from: data)
			return PaginatedResponse(items: envelope.items.map { $0.resolved }, page: envelope.page, limit: envelope.limit, total: envelope.total, hasMore: envelope.hasMore)
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}
}
