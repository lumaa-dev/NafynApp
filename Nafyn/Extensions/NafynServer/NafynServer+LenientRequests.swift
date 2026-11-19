// Made by Lumaa

import Foundation
import Safyn

/// `Request.all`'s `requestedBy` is resolved server-side via a compact user projection (confirmed
/// against `requests.ts`'s `rowToRequest`, which calls `getUserById(id, compact: true)`) — an object
/// missing `permissions`/`listenBrainz`/`discogs`. `UserRef.init(from:)` tries to decode that object as a full
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
	///
	/// `filters` narrows the list to those statuses; empty means every request. The server only knows four
	/// groups (`succeeded`/`failed`/`waiting`/`processing`) and always lists `denied`, so with a filter
	/// active denied requests are dropped here unless `.denied` was picked.
	///
	/// `type` keeps only album or only track requests, `user` only one account's (``Request/requesters`` lists them);
	/// `nil` keeps all of them. Same query items as Safyn's `Request.all(type:user:)`.
	func fetchRequests(page: Int, limit: Int, filters: Set<RequestFilter> = [], type: RequestKind? = nil, user: String? = nil) async throws -> PaginatedResponse<NafynRequest> {
		var queryItems = [
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "limit", value: String(limit)),
		]
		if let type {
			queryItems.append(URLQueryItem(name: "type", value: type.rawValue))
		}
		if let user {
			queryItems.append(URLQueryItem(name: "user", value: user))
		}
		if !filters.isEmpty {
			queryItems += [
				URLQueryItem(name: "succeeded", value: String(filters.contains(.succeeded))),
				URLQueryItem(name: "failed", value: String(filters.contains(.failed))),
				URLQueryItem(name: "waiting", value: String(filters.contains(.waiting))),
				URLQueryItem(name: "processing", value: String(filters.contains(.inProgress))),
			]
		}
		let data = try await self.fetchGET(path: "/api/v1/requests", queryItems: queryItems)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			let envelope = try decoder.decode(RawPaginatedEnvelope<LenientNafynRequest>.self, from: data)
			let requests = envelope.items.map { $0.resolved }.filter { request in
				// denied and cancelled have no server filter: they are always listed, so dropped here unless picked
				if filters.isEmpty { return true }
				switch request.status {
					case .denied: return filters.contains(.denied)
					case .cancelled: return filters.contains(.cancelled)
					default: return true
				}
			}
			return PaginatedResponse(items: requests, page: envelope.page, limit: envelope.limit, total: envelope.total, hasMore: envelope.hasMore)
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}
}
