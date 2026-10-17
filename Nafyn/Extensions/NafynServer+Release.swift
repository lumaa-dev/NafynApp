// Made by Lumaa

import Foundation
import Safyn

/// A track lookup plus the release fields Safyn's `TrackDetail` doesn't model yet (`released`, `subscribed`,
/// `releaseDatePrecision`, added to `GET /api/v1/track/{id}` alongside the album ones).
struct TrackRelease {
	let detail: TrackDetail
	let released: Bool
	let subscribed: Bool
	let precision: ReleaseDatePrecision?
}

private struct TrackReleaseExtras: Decodable {
	let released: Bool?
	let subscribed: Bool?
	let releaseDatePrecision: ReleaseDatePrecision?
}

extension NafynServer {
	/// `Track.get(tid:)` with the release fields read from the same response.
	func fetchTrackRelease(tid: String) async throws -> TrackRelease {
		let data = try await self.sendRaw(Track.get(tid: tid))
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			let detail = try decoder.decode(TrackDetail.self, from: data)
			let extras = try decoder.decode(TrackReleaseExtras.self, from: data)
			return TrackRelease(detail: detail, released: extras.released ?? true, subscribed: extras.subscribed ?? false, precision: extras.releaseDatePrecision)
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}

	/// Follows (`true`) or unfollows (`false`) an unreleased album/track; returns the new state.
	@discardableResult
	func setFollowing(_ follow: Bool, mbid: String, type: ReleaseSubscriptionKind) async throws -> Bool {
		if follow {
			_ = try await self.send(Subscriptions.create(id: mbid, type: type, timezone: TimeZone.current.identifier)) as ReleaseSubscription
		} else {
			_ = try await self.sendRaw(Subscriptions.delete(mbid: mbid))
		}
		return follow
	}
}
