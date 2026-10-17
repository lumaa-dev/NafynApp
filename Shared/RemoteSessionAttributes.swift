// Made by Lumaa

import Foundation
import NowPlaying

/// `aps.attributes` of the server's `nowplaying` pushes, shared by the app (push-to-start token) and the
/// remote-session extension (content + commands). Field names match `server/utils/apn.ts` exactly.
///
/// `end` pushes carry only `id`, hence every other field being optional.
struct NafynRemoteSessionAttributes: RemoteMediaSessionAttributes, Equatable {
	struct Device: Codable, Equatable {
		var id: String
		var name: String

		/// `computer`, `phone`, `tablet` or `speaker`.
		var type: String

		/// `0...1`.
		var volume: Double
	}

	struct Track: Codable, Equatable {
		var id: String
		var title: String
		var artist: String
		var album: String?
		var duration: Double

		/// Only set when the cover is a public https URL.
		var artworkURL: String?
	}

	var id: String
	var devices: [Device]?
	var isPlaying: Bool?
	var currentTrackIndex: Int?
	var queueCount: Int?

	/// Seconds into the track at ``timestamp``.
	var elapsedTime: Double?

	/// ISO 8601 instant ``elapsedTime`` was sampled at, with fractional seconds. Kept a `String` so decoding
	/// doesn't depend on whichever date strategy the system decoder uses; read it through ``timestampDate``.
	var timestamp: String?
	var currentTrack: Track?

	var timestampDate: Date? {
		guard let timestamp else { return nil }
		return Self.fractionalFormatter.date(from: timestamp) ?? Self.plainFormatter.date(from: timestamp)
	}

	/// Where playback is now: the sampled position, advanced by the time since the sample while playing.
	func elapsed(at now: Date = .now) -> Double {
		let base = self.elapsedTime ?? 0
		guard self.isPlaying == true, let sampled = self.timestampDate else { return base }
		let value = base + now.timeIntervalSince(sampled)
		guard let duration = self.currentTrack?.duration, duration > 0 else { return max(0, value) }
		return min(max(0, value), duration)
	}

	private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private nonisolated(unsafe) static let plainFormatter = ISO8601DateFormatter()
}
