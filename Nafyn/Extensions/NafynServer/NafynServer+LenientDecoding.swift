// Made by Lumaa

import Foundation
import Safyn

/// The Nafyn server's "compact" user projection (used for a playlist's `owner`/`members`/`addedBy`, and
/// for a request's `requestedBy`) omits `permissions`, `listenBrainz`, and `discogs` entirely — but Safyn's
/// `NafynUser` declares `permissions` as a required field with no default, so decoding those nested
/// users via the normal `NafynUser: Decodable` synthesis throws `keyNotFound("permissions")`.
///
/// This mirror decodes the same JSON permissively (falling back to `[]`/`nil`) and rebuilds the real
/// Safyn model through its public initializer. Shared by every lenient-decoding workaround that embeds
/// a compact user somewhere in its response.
struct LenientUser: Decodable {
	let id: String
	let username: String
	let displayName: String?
	let avatar: String?
	let permissions: Permissions?
	let listenBrainz: String?
	let discogs: String?

	var resolved: NafynUser {
		NafynUser(id: id, username: username, displayName: displayName, avatar: avatar, permissions: permissions ?? [], listenBrainz: listenBrainz, discogs: discogs)
	}
}

/// Mirrors `UserRef`'s decode strategy (object shape first, string fallback) using ``LenientUser``
/// instead of `NafynUser`, so a compact user object doesn't fall through to the string branch (where it
/// would throw `typeMismatch`, since it's an object, not a string) the way `UserRef.init(from:)` does.
enum LenientUserRef: Decodable {
	case user(LenientUser)
	case id(String)

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let user = try? container.decode(LenientUser.self) {
			self = .user(user)
		} else {
			self = .id(try container.decode(String.self))
		}
	}

	var resolved: UserRef {
		switch self {
			case .user(let user):
				.user(user.resolved)
			case .id(let id):
				.id(id)
		}
	}
}

/// A raw mirror of Safyn's `PaginatedResponse` envelope, generic over a lenient item mirror rather than
/// the real (strict) model — used by every lenient paginated fetch.
struct RawPaginatedEnvelope<RawItem: Decodable>: Decodable {
	let items: [RawItem]
	let page: Int
	let limit: Int
	let total: Int
	let hasMore: Bool
}
