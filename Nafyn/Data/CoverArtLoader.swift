// Made by Lumaa

import Foundation
import UIKit
import Safyn

/// Loads Cover Art Archive covers through the server's cache (`Library.coverArt`) rather than from the
/// archive itself, and keeps what it loaded in memory.
///
/// Concurrent requests for one cover share a single fetch, the server's `504` ("not cached yet, the archive
/// was too slow") is retried a few times as its docs ask, and a `404` ("the archive has no cover") is
/// remembered so a cover-less album isn't asked for again on every render. Fetching and image decoding both
/// happen off the main thread.
///
/// Not an actor on purpose: `CoverImage` needs a synchronous cache lookup in `body` so a cover that was
/// already loaded never flashes its placeholder.
final class CoverArtLoader: @unchecked Sendable {
	static let shared = CoverArtLoader()

	private static let maxAttempts = 4
	private static let retryDelay: Duration = .seconds(1.5)

	private let lock = NSLock()
	private var server: NafynServer?
	private var inFlight: [String: Task<Data?, Never>] = [:]
	private var missing: Set<String> = []

	private let dataCache = NSCache<NSString, NSData>()
	private let imageCache = NSCache<NSString, UIImage>()

	private init() {
		self.dataCache.totalCostLimit = 64 * 1024 * 1024
		self.imageCache.totalCostLimit = 96 * 1024 * 1024
	}

	/// Binds the loader to the logged-in server. Called alongside `PlayerEngine.configure(server:)`.
	func configure(server: NafynServer) {
		self.lock.lock()
		defer { self.lock.unlock() }
		self.server = server
		// A cover that was missing a moment ago may exist on the new account's server.
		self.missing = []
	}

	/// Whether covers can be fetched through the server — `false` while logged out / on the offline library.
	var isConfigured: Bool {
		self.lock.lock()
		defer { self.lock.unlock() }
		return self.server != nil
	}

	// MARK: - Cache

	/// An already-decoded image, if this cover was loaded before. Synchronous and cheap.
	func cachedImage(for url: URL) -> UIImage? {
		guard let reference = CoverArtReference(url: url) else { return nil }
		return self.imageCache.object(forKey: reference.cacheKey as NSString)
	}

	// MARK: - Loading

	/// The decoded cover for `url`, or `nil` when it isn't a Cover Art Archive URL, the archive has no
	/// cover, or it couldn't be fetched.
	func image(for url: URL) async -> UIImage? {
		guard let reference = CoverArtReference(url: url) else { return nil }
		let key = reference.cacheKey as NSString

		if let cached = self.imageCache.object(forKey: key) {
			return cached
		}
		guard let data = await self.data(for: reference) else { return nil }

		let image = await Task.detached(priority: .userInitiated) {
			UIImage(data: data)?.preparingForDisplay()
		}.value

		if let image {
			let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
			self.imageCache.setObject(image, forKey: key, cost: cost)
		}
		return image
	}

	/// The raw `image/jpeg` bytes for `url`, for consumers that want data rather than an image (Now Playing
	/// artwork, palette extraction). `nil` under the same conditions as `image(for:)`.
	func data(for url: URL) async -> Data? {
		guard let reference = CoverArtReference(url: url) else { return nil }
		return await self.data(for: reference)
	}

	private func data(for reference: CoverArtReference) async -> Data? {
		let key = reference.cacheKey

		if let cached = self.dataCache.object(forKey: key as NSString) {
			return cached as Data
		}

		let task: Task<Data?, Never>? = self.lock.withLock {
			if self.missing.contains(key) { return nil }
			if let existing = self.inFlight[key] { return existing }
			guard let server = self.server else { return nil }

			// Unstructured on purpose: a view scrolling away cancels *its* wait, not the shared fetch.
			let task = Task.detached(priority: .userInitiated) { [weak self] in
				await self?.fetch(reference, from: server)
			}
			self.inFlight[key] = task
			return task
		}
		return await task?.value
	}

	private func fetch(_ reference: CoverArtReference, from server: NafynServer) async -> Data? {
		let key = reference.cacheKey
		defer { self.lock.withLock { _ = self.inFlight.removeValue(forKey: key) } }

		for attempt in 1...Self.maxAttempts {
			do {
				let data = try await server.sendRaw(reference.endpoint)
				guard !data.isEmpty else { return nil }
				self.dataCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
				return data
			} catch NafynError.server(let statusCode, _) where statusCode == 404 {
				self.lock.withLock { _ = self.missing.insert(key) }
				return nil
			} catch NafynError.server(let statusCode, _) where statusCode == 504 && attempt < Self.maxAttempts {
				try? await Task.sleep(for: Self.retryDelay)
			} catch {
				return nil
			}
		}
		return nil
	}
}
