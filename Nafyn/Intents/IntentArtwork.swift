// Made by Lumaa

import Foundation
import Safyn

/// Small covers kept on disk for the places that ask for an image *synchronously*: Spotlight's attribute set,
/// and the picture next to a result in Siri and Shortcuts. The covers themselves live on the server and need
/// the session's auth, so they are fetched ahead (`prefetch`, run by the Spotlight sync) and read back by
/// path. An entity without its cover on disk yet simply has no picture; the next sync adds it.
nonisolated enum IntentArtwork {
	/// The server's smallest size: ample for a Spotlight row, and ~20 KB per album.
	private static let pixels: UInt16 = 250

	private static let concurrentDownloads = 6

	private static let memory = NSCache<NSString, NSData>()

	private static var directory: URL {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		return caches.appendingPathComponent("IntentArtwork", isDirectory: true)
	}

	/// Server cover paths name their cover (`/api/v1/art/<type>/<id>/<size>`): the type and ID are the key.
	private static func key(for coverArt: String) -> String? {
		guard let url = URL(string: coverArt), let reference = CoverArtReference(url: url) else { return nil }
		return "\(reference.kind.rawValue)-\(reference.id)"
	}

	/// The stored cover for a server cover path, if it was prefetched. Cheap enough to call per entity.
	static func data(for coverArt: String?) -> Data? {
		guard let coverArt, let key = self.key(for: coverArt) else { return nil }

		if let cached = self.memory.object(forKey: key as NSString) { return cached as Data }
		guard let data = try? Data(contentsOf: self.directory.appendingPathComponent("\(key).jpg")), !data.isEmpty else { return nil }

		self.memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
		return data
	}

	/// Downloads the covers that aren't stored yet. Needs the session (`CoverArtLoader` is configured by then).
	static func prefetch(_ coverArts: [String?]) async {
		let directory = self.directory
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		var wanted: [String: URL] = [:]
		for coverArt in coverArts {
			guard let coverArt, let key = self.key(for: coverArt), wanted[key] == nil,
				  !FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(key).jpg").path),
				  let url = coverArt.coverArtURL(size: self.pixels)
			else { continue }
			wanted[key] = url
		}
		guard !wanted.isEmpty else { return }

		var pending = Array(wanted)
		await withTaskGroup(of: Void.self) { group in
			func enqueue() {
				guard let (key, url) = pending.popLast() else { return }
				group.addTask {
					guard let data = await CoverArtLoader.shared.data(for: url), !data.isEmpty else { return }
					try? data.write(to: directory.appendingPathComponent("\(key).jpg"), options: .atomic)
				}
			}

			for _ in 0..<Self.concurrentDownloads { enqueue() }
			while await group.next() != nil { enqueue() }
		}
	}

	/// Forgets every stored cover (signed out).
	static func removeAll() {
		self.memory.removeAllObjects()
		try? FileManager.default.removeItem(at: self.directory)
	}
}
