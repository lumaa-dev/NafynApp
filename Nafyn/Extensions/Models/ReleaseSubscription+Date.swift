// Made by Lumaa

import Foundation
import Safyn

extension ReleaseSubscription {
	/// The release day as UTC midnight, the same shape the album/track endpoints send, so it feeds
	/// ``ReleaseCountdown`` unchanged.
	var releaseDay: Date? {
		var utc = Calendar(identifier: .gregorian)
		utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
		let parts = self.releaseDate.prefix(10).split(separator: "-").compactMap { Int($0) }
		guard parts.count == 3 else { return nil }
		return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
	}
}
