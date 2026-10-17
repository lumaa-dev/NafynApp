// Made by Lumaa

import Foundation

/// Where a notification tap, a Live Activity tap or a `nafyn://` URL leads.
enum DeepLink: Equatable {
	case path(Navigator.Paths)
	case requests

	/// Parses the `nafyn` dictionary the server puts next to `aps` (see `server/utils/apn.ts`):
	/// `musicbrainzId` + `type` open the album/track screen; a `requestId` alone opens the Requests tab.
	init?(userInfo: [AnyHashable: Any]) {
		guard let payload = userInfo["nafyn"] as? [String: Any] else { return nil }

		if let mbid = payload["musicbrainzId"] as? String, !mbid.isEmpty, let type = payload["type"] as? String {
			switch type {
				case "album": self = .path(.album(id: mbid))
				case "track": self = .path(.track(id: mbid))
				default: return nil
			}
		} else if let requestId = payload["requestId"] as? String, !requestId.isEmpty {
			self = .requests
		} else {
			return nil
		}
	}

	/// `nafyn://album/<mbid>`, `nafyn://track/<mbid>` and `nafyn://requests`.
	init?(url: URL) {
		guard url.scheme == "nafyn", let host = url.host() else { return nil }
		let id = url.pathComponents.dropFirst().first

		switch (host, id) {
			case ("album", let id?): self = .path(.album(id: id))
			case ("track", let id?): self = .path(.track(id: id))
			case ("requests", _): self = .requests
			default: return nil
		}
	}

	/// Whether the user is already looking at this destination.
	var isCurrentlyVisible: Bool {
		let navigator = Navigator.shared
		switch self {
			case .path(let path):
				return navigator.sheet == nil && navigator.currentPath[navigator.currentTab]?.last == path
			case .requests:
				return navigator.currentTab == .requests && (navigator.currentPath[.requests] ?? []).isEmpty
		}
	}

	func open() {
		switch self {
			case .path(let path):
				Navigator.shared.send(to: path)
			case .requests:
				Navigator.shared.currentTab = .requests
		}
	}

	/// Live Activities can't carry a `Navigator.Paths`, so they link by URL.
	static func url(type: String, musicbrainzId: String) -> URL? {
		URL(string: "nafyn://\(type)/\(musicbrainzId)")
	}
}
