// Made by Lumaa

import Foundation
import Safyn

extension MediaRow {
	/// The largest cover the server offers, for Now Playing and lock-screen artwork.
	var highResCoverURL: URL? {
		self.setCoverSize(UInt16(CoverArtSize.large.rawValue))
	}

	func setCoverSize(_ size: UInt16) -> URL? {
		guard var coverArt else { return nil }
		coverArt.replace(/\d+$/, with: "\(size)")

		return URL(string: coverArt)
	}
}
