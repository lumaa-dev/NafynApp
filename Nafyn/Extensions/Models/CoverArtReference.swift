// Made by Lumaa

import Foundation
import Safyn

/// A server-cached cover, identified by what `Library.coverArt(type:id:size:token:)` needs.
///
/// Nafyn's `coverArt` fields are paths relative to the server (`/api/v1/art/<type>/<id>/<size>`), so they
/// can't be loaded as they are: `CoverArtLoader` resolves them against the current session's server and
/// sends its auth. Anything that isn't such a path (uploaded track covers, playlist images, avatars,
/// artist photos) has no reference and keeps loading from its own URL.
nonisolated struct CoverArtReference: Hashable, Sendable {
	let kind: CoverArtKind
	let id: String
	let size: CoverArtSize

	/// Parses a server cover path, `/api/v1/art/<type>/<id>/<size>`, absolute or relative.
	init?(url: URL) {
		let parts = url.pathComponents.filter { $0 != "/" }

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
