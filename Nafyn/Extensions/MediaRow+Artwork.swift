// Made by Lumaa

import Foundation
import Safyn

extension MediaRow {
	/// The largest cover the server offers, for Now Playing and lock-screen artwork.
	var highResCoverURL: URL? {
		self.setCoverSize(UInt16(CoverArtSize.large.rawValue))
	}

	func setCoverSize(_ size: UInt16) -> URL? {
		self.coverArt?.coverArtURL(size: size)
	}
}

extension String {
	/// A server `coverArt` path (`/api/v1/art/<type>/<id>/<size>`) at another size (250 / 500 / 1000).
	nonisolated func coverArtURL(size: UInt16) -> URL? {
		URL(string: self.replacing(/\d+$/, with: "\(size)"))
	}
}
