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

	/// A link that arrived before the tabs were on screen (cold start from a notification, Live Activity or
	/// URL, while `RootView` is still logging in). Pushing it then would seed a `NavigationStack` that doesn't
	/// exist yet, so it waits here until `RootView` reports the tabs are mounted.
	private static var pending: DeepLink?
	private static var isReady = false

	/// Called by `RootView` when the tabs appear / disappear (login, account switch, sign-out).
	static func setReady(_ ready: Bool) {
		isReady = ready
		guard ready, let link = pending else { return }
		pending = nil

		// let the freshly mounted `NavigationStack`s settle before pushing onto them
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(400))
			link.navigate()
		}
	}

	func open() {
		guard Self.isReady else {
			Self.pending = self
			return
		}
		self.navigate()
	}

	private func navigate() {
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
