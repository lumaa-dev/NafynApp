// Made by Lumaa

import Foundation
import Safyn

/// Insights helpers for the response shapes the OpenAPI spec leaves untyped, plus the two endpoints
/// that serve bytes rather than JSON (`export`, `reelVideo`).
extension NafynServer {
	/// `Insights.top(...)`, tolerant of both shapes the untyped `/insights/top` schema permits: a bare
	/// array of ranked entities, or the usual `{ items: [...] }` pagination envelope.
	func insightsTop(
		type: RankedEntityKind,
		period: String,
		week: String? = nil,
		month: String? = nil,
		year: Int? = nil
	) async throws -> [RankedEntity] {
		var queryItems: [URLQueryItem] = [
			URLQueryItem(name: "type", value: type.rawValue),
			URLQueryItem(name: "period", value: period),
		]
		if let week {
			queryItems.append(URLQueryItem(name: "week", value: week))
		}
		if let month {
			queryItems.append(URLQueryItem(name: "month", value: month))
		}
		if let year {
			queryItems.append(URLQueryItem(name: "year", value: String(year)))
		}

		let data = try await self.fetchGET(path: "/api/v1/insights/top", queryItems: queryItems)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		if let entities = try? decoder.decode([RankedEntity].self, from: data) {
			return entities
		}
		if let envelope = try? decoder.decode(RawPaginatedEnvelope<RankedEntity>.self, from: data) {
			return envelope.items
		}
		throw NafynError.decoding("Unexpected /insights/top response shape")
	}

	/// The full listening-data export, as the raw JSON document the server produced.
	///
	/// Deliberately untyped: the document's shape is versioned by a `format` field inside it rather than
	/// by this client, so it's handed to the user as-is.
	func insightsExport() async throws -> Data {
		try await self.sendRaw(Insights.export)
	}

	/// A directly-loadable URL for a year's rendered highlight-reel MP4, token included.
	///
	/// `AVPlayer` fetches its own bytes and can't be handed an `Authorization` header, which is why this
	/// endpoint accepts the token as a query parameter.
	func reelVideoURL(year: Int) -> URL? {
		self.absoluteURL(for: Insights.reelVideo(year: year, token: self.authToken))
	}

	/// A directly-loadable stream URL for one media ID, for the highlight reel's audio excerpts.
	func mediaStreamURL(id: String) -> URL? {
		self.absoluteURL(for: Library.stream(id: id, token: self.authToken))
	}

	/// Resolves an endpoint's path and queries against this server's base URL.
	private func absoluteURL<E: NafynEndpoint>(for endpoint: E) -> URL? {
		guard var components = URLComponents(url: self.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		return components.url
	}
}
