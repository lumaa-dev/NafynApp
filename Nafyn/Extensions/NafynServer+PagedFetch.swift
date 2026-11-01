// Made by Lumaa

import Foundation
import Safyn

/// Safyn's `Library.albums/tracks`, `Playlist.list/tracks`, `Request.all`, and `Users.all` endpoints
/// send `?offset=`, but the Nafyn server's `parsePagination` only ever reads `?page=`/`?limit=` — so
/// paging through those 6 endpoints via their built-in `queries` silently sticks on page 1 forever.
///
/// This bypasses that broken query-building for just those endpoints, hand-building a `?page=&limit=`
/// request against the same paths and decoding the `PaginatedResponse` envelope every one of them
/// actually returns server-side (confirmed against the Nafyn server source, not just its OpenAPI spec).
extension NafynServer {
	/// A library list (`/library/tracks`, `/library/albums`) narrowed and ordered by the server. Safyn's
	/// `Library.tracks/albums(query:sort:)` carry the same parameters but send `?offset=` instead of `?page=`, so
	/// the paging stays on ``fetchPaginated(path:page:limit:extraQueryItems:)`` and only the query items are borrowed.
	func fetchLibraryPage<Item: Decodable & Sendable & Hashable>(path: String, page: Int, limit: Int, query: String, sort: LibrarySort) async throws -> PaginatedResponse<Item> {
		let endpoint = path.hasSuffix("albums") ? Library.albums(query: query, sort: sort).queries : Library.tracks(query: query, sort: sort).queries
		return try await self.fetchPaginated(path: path, page: page, limit: limit, extraQueryItems: endpoint)
	}

	/// Issues an authenticated `GET` against `path` with the given query items, returning the raw response body.
	///
	/// Shared low-level plumbing for every local workaround that needs to bypass a Safyn `NafynEndpoint`
	/// (broken query building, or a response shape `NafynServer.send` can't decode as-is).
	func fetchGET(path: String, queryItems: [URLQueryItem]) async throws -> Data {
		guard var components = URLComponents(url: instance.baseURL, resolvingAgainstBaseURL: false) else {
			throw NafynError.invalidURL
		}
		components.path += path
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}
		guard let url = components.url else {
			throw NafynError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		if let authToken {
			request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		}

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw NafynError.transport(error.localizedDescription)
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			throw NafynError.invalidResponse
		}
		guard (200..<300).contains(httpResponse.statusCode) else {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			if let nuxtError = try? decoder.decode(NuxtError.self, from: data) {
				throw NafynError.server(statusCode: httpResponse.statusCode, error: nuxtError)
			}
			throw NafynError.invalidResponse
		}

		return data
	}

	/// - Parameter extraQueryItems: Further query items (the library lists' `q` and `sort`).
	func fetchPaginated<Item: Decodable & Sendable & Hashable>(path: String, page: Int, limit: Int, extraQueryItems: [URLQueryItem] = []) async throws -> PaginatedResponse<Item> {
		let data = try await self.fetchGET(path: path, queryItems: [
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "limit", value: String(limit)),
		] + extraQueryItems)

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			return try decoder.decode(PaginatedResponse<Item>.self, from: data)
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}
}
