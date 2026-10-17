// Made by Lumaa

import Foundation
import NowPlaying
import Safyn

/// Reports the Now Playing remote-session push-to-start token (`nowplaying-start`) to the server, so it can
/// start a session here whenever another device is the Nafyn Unity master.
///
/// The per-session update token is reported by the extension that owns the session (it's a separate
/// process; see `RemoteMediaSessionExtension`).
final class RemoteMediaCoordinator {
	static let shared = RemoteMediaCoordinator()

	private var hasStarted = false

	private init() {}

	func start() {
		guard !self.hasStarted else { return }
		self.hasStarted = true

		Task {
			if let token = RemoteMediaSession<NafynRemoteSessionAttributes>.pushToStartToken {
				PushManager.shared.submit(token: token, kind: .nowPlayingStart)
			}
			for await token in RemoteMediaSession<NafynRemoteSessionAttributes>.pushToStartTokenUpdates {
				PushManager.shared.submit(token: token, kind: .nowPlayingStart)
			}
		}
	}

	/// Asks the system to show the current remote session in Now Playing. Only to be called when the user
	/// explicitly opens it, with the app in the foreground (Apple's requirement, or the request is ignored).
	func presentCurrentSession() async {
		guard let session = try? await RemoteMediaSession<NafynRemoteSessionAttributes>.sessions().first else { return }
		try? await session.requestToBecomeSystemPrimary()
	}

	/// Whether a remote session is currently running for this device.
	var hasSession: Bool {
		get async {
			let sessions = try? await RemoteMediaSession<NafynRemoteSessionAttributes>.sessions()
			return !(sessions?.isEmpty ?? true)
		}
	}
}
