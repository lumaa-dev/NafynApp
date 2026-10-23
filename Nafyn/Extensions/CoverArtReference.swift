// Made by Lumaa

import Foundation
import Safyn

/// A Cover Art Archive cover, identified by what `Library.coverArt(type:id:size:token:)` needs.
///
/// Nafyn's `coverArt` fields are plain Cover Art Archive URLs (`…/release-group/<mbid>/front-500`). Those
/// are fetched through the server's cache endpoint instead of hitting the archive directly — the archive
/// is slow and rate limited, the server's cache is neither. Anything that isn't such a URL (uploaded track
/// covers, playlist images, avatars, artist photos) has no reference and keeps loading from its own URL.
struct CoverArtReference: Hashable, Sendable {
	let kind: CoverArtKind
	let id: String
	let size: CoverArtSize

	/// Parses a Cover Art Archive URL, or the server's own `…/art/<type>/<id>/<size>` URL.
	init?(url: URL) {
		let parts = url.pathComponents.filter { $0 != "/" }

		if let host = url.host?.lowercased(), host == "coverartarchive.org" || host.hasSuffix(".coverartarchive.org") {
			guard let index = parts.firstIndex(where: { CoverArtKind(rawValue: $0) != nil }),
				  let kind = CoverArtKind(rawValue: parts[index]),
				  parts.indices.contains(index + 1)
			else { return nil }

			self.kind = kind
			self.id = parts[index + 1]
			// `front-250`, `front-500`, `front-1200`, or a bare `front`
			let pixels = parts.last?.split(separator: "-").last.flatMap { Int($0) }
			self.size = Self.size(forPixels: pixels)
			return
		}

		// The server's own cache endpoint: .../art/<type>/<id>/<size>
		guard let art = parts.firstIndex(of: "art"),
			  parts.indices.contains(art + 3),
			  let kind = CoverArtKind(rawValue: parts[art + 1])
		else { return nil }

		self.kind = kind
		self.id = parts[art + 2]
		self.size = Self.size(forPixels: Int(parts[art + 3]))
	}

	/// The smallest size the server offers that is at least `pixels`, capped at its largest.
	private static func size(forPixels pixels: Int?) -> CoverArtSize {
		guard let pixels else { return .medium }
		switch pixels {
			case ...250: return .small
			case ...500: return .medium
			default: return .large
		}
	}

	var endpoint: Library {
		Library.coverArt(type: self.kind, id: self.id, size: self.size)
	}

	/// Stable cache key — one entry per cover and size.
	var cacheKey: String {
		"\(self.kind.rawValue)/\(self.id)/\(self.size.rawValue)"
	}
}
