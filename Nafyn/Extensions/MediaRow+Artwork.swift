// Made by Lumaa

import Foundation
import Safyn

extension MediaRow {
	/// Cover Art Archive URLs (Nafyn's `coverArt` fields) embed a fixed-size suffix like `front-250` or
	/// `front-500`. Rewriting it to a larger fixed size makes both the on-screen Now Playing cover and
	/// the lock-screen/Control Center artwork sharp instead of upscaled-blurry — there's no "give me a
	/// bigger image" query parameter on either the URL or the `MPMediaItemArtwork` API, so the only way
	/// to get a bigger image is to ask Cover Art Archive for one directly.
	var highResCoverURL: URL? {
		guard let coverArt else { return nil }
		let highRes = coverArt
			.replacingOccurrences(of: "front-250", with: "front-1200")
			.replacingOccurrences(of: "front-500", with: "front-1200")
		return URL(string: highRes)
	}
}
