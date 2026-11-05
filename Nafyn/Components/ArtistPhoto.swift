// Made by Lumaa

import SwiftUI
import OSLog
import Safyn

/// Looks artists' pictures up (`Artist.image`) and remembers the answers for the session. A lookup hits
/// MusicBrainz and a few photo sources server-side and is rate limited, so lookups run a few at a time and an
/// answer, including "no picture", is only asked for once. A failure (offline, 429, 503) isn't remembered.
@MainActor
final class ArtistImageLoader {
	static let shared = ArtistImageLoader()

	private static let maxConcurrentLookups = 3
	private static let maxAttempts = 3
	private static let logger = Logger(subsystem: "fr.lumaa.Nafyn", category: "ArtistImage")

	/// `.some(nil)` means the server has no picture for that artist.
	private var resolved: [String: URL?] = [:]
	private var inFlight: [String: Task<URL?, Never>] = [:]

	private var activeLookups = 0
	private var waiting: [CheckedContinuation<Void, Never>] = []

	private init() {}

	/// The answer already known, without asking: `nil` when not looked up yet, `.some(nil)` for "no picture".
	func cachedURL(for artistId: String) -> URL?? {
		self.resolved[artistId]
	}

	func url(for artistId: String, server: NafynServer?) async -> URL? {
		if let known = self.resolved[artistId] { return known }
		if let task = self.inFlight[artistId] { return await task.value }
		guard let server else { return nil }

		let task = Task { [weak self] () -> URL? in
			guard let self else { return nil }

			// 429 ("too many lookups") and 503 (MusicBrainz is down) are asked again a little later: the slot is
			// handed back while waiting, and nothing is remembered until the server really answered
			for attempt in 0..<Self.maxAttempts {
				await self.acquireSlot()
				do {
					let response: ArtistImageResponse = try await server.send(Artist.image(aid: artistId))
					self.releaseSlot()
					let url = response.image.flatMap { URL(string: $0) }
					self.resolved[artistId] = .some(url)
					return url
				} catch {
					self.releaseSlot()
					guard Self.isTemporary(error), attempt < Self.maxAttempts - 1 else {
						Self.logger.error("artist image lookup failed: \(error.localizedDescription, privacy: .public)")
						return nil
					}
					try? await Task.sleep(for: .seconds(3 * (attempt + 1)))
				}
			}
			return nil
		}
		self.inFlight[artistId] = task
		let url = await task.value
		self.inFlight[artistId] = nil
		return url
	}

	private static func isTemporary(_ error: Error) -> Bool {
		if case NafynError.server(let statusCode, _) = error {
			return statusCode == 429 || statusCode == 503
		}
		return false
	}

	private func acquireSlot() async {
		if self.activeLookups < Self.maxConcurrentLookups {
			self.activeLookups += 1
			return
		}
		await withCheckedContinuation { self.waiting.append($0) }
	}

	private func releaseSlot() {
		if self.waiting.isEmpty {
			self.activeLookups -= 1
		} else {
			// the slot passes straight to the next lookup in line
			self.waiting.removeFirst().resume()
		}
	}
}

/// An artist's picture: the one the server finds for them, else `fallback` (what the artist's own metadata
/// carries, if anything), else the placeholder. Clip it to the shape you need.
struct ArtistPhoto: View {
	@Environment(\.server) private var server: NafynServer?

	/// The artist's MusicBrainz ID. Without one there's nothing to look up and only `fallback` shows.
	let artistId: String?
	var fallback: URL? = nil
	var cornerRadius: CGFloat = 0

	@State private var found: URL? = nil

	private var shown: URL? {
		if let found { return found }
		if let artistId, let cached = ArtistImageLoader.shared.cachedURL(for: artistId), let url = cached { return url }
		return self.fallback
	}

	var body: some View {
		CoverImage(url: self.shown, cornerRadius: self.cornerRadius)
			.task(id: self.artistId) {
				guard let artistId, ArtistImageLoader.shared.cachedURL(for: artistId) == nil else { return }
				self.found = await ArtistImageLoader.shared.url(for: artistId, server: self.server)
			}
	}
}
