// Made by Lumaa

import Foundation
import ActivityKit

/// Live Activity for a download request. Started by the server through push-to-start, never locally.
///
/// The type name is part of the contract: the server names it (`attributes-type`) in its push-to-start
/// payload, so renaming either type here silently breaks the activity. The server encodes `ContentState`
/// as plain camelCase JSON with explicit nulls, which the default `Codable` synthesis below matches.
struct NafynRequestActivityAttributes: ActivityAttributes {
	static let ginkgo: Self = .init(requestId: "ABC", type: "album", title: "Gingko", artistName: "Panchiko")
	static let cmiygl: Self = .init(requestId: "ABC", type: "album", title: "CALL ME IF YOU GET LOST: The Estate Sale", artistName: "Tyler, The Creator")

	struct ContentState: Codable, Hashable {
		static let lifestyleTrainers: Self = .init(
			stage: .downloading,
			message: "Message",
			trackTitle: "Lifestyle Trainers",
			trackIndex: 6,
			trackCount: 13,
			progress: 0.0,
			etaSeconds: nil
		)

		static let sorryNotSorry: Self = .init(
			stage: .downloading,
			message: "Message",
			trackTitle: "SORRY NOT SORRY",
			trackIndex: 24,
			trackCount: 24,
			progress: 0.0,
			etaSeconds: nil
		)

		enum Stage: String, Codable, Hashable {
			case waiting
			case searching
			case downloading
			case processing
			case completed
			case failed
		}

		var stage: Self.Stage
		var message: String?
		var trackTitle: String?
		var trackIndex: Int?
		var trackCount: Int?

		/// `0...1` for the current track's download.
		var progress: Double?
		var etaSeconds: Double?
	}

	var requestId: String

	/// `album` or `track`.
	var type: String
	var title: String
	var artistName: String
	var coverArt: String?
}

/// Live Activity counting down to an unreleased album/track, started by the server 3 hours before the release.
struct NafynReleaseCountdownAttributes: ActivityAttributes {
	static let gingko: Self = .init(subscriptionId: "ABC", musicbrainzId: "DEF", type: "album", title: "Gingko", artistName: "Panchiko")
	static let cmiygl: Self = .init(subscriptionId: "ABC", musicbrainzId: "DEF", type: "album", title: "CALL ME IF YOU GET LOST: The Estate Sale", artistName: "Tyler, The Creator")

	struct ContentState: Codable, Hashable {
		static let wks: Self = .init(releaseAt: 1792859061, released: false)
		static let hrs: Self = .init(releaseAt: 1792243461, released: false)

		/// **Unix seconds.** Deliberately a `TimeInterval` rather than a `Date`: ActivityKit decodes the push's
		/// content state with a default `JSONDecoder`, whose `Date` strategy counts from 2001, which would put
		/// the countdown 31 years off. Convert with ``releaseDate``.
		var releaseAt: TimeInterval
		var released: Bool

		var releaseDate: Date {
			Date(timeIntervalSince1970: self.releaseAt)
		}
	}

	var subscriptionId: String
	var musicbrainzId: String

	/// `album` or `track`.
	var type: String
	var title: String
	var artistName: String
	var coverArt: String?
}
