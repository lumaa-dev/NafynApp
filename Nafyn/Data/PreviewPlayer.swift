// Made by Lumaa

import AVFoundation
import Observation
import Safyn

/// The 30-second iTunes preview of a track the user doesn't own (`Track.preview`), on the catalog track and album
/// screens. One at a time, on its own `AVPlayer` - never `PlayerEngine`'s: a preview is no listen (no statistics, no
/// queue, no Nafyn Unity). The player is paused while one plays, and starting the player ends the preview.
@MainActor
@Observable
final class PreviewPlayer {
	static let shared = PreviewPlayer()

	/// The recording whose preview is playing.
	private(set) var playingId: String?
	/// The recording whose preview is loading.
	private(set) var loadingId: String?
	/// Recordings iTunes has no preview of (the server answered 404), so their button can say so.
	private(set) var unavailableIds: Set<String> = []

	@ObservationIgnored private var player: AVPlayer?
	@ObservationIgnored private var observers: [NSObjectProtocol] = []
	@ObservationIgnored private var statusObservation: NSKeyValueObservation?

	private init() {}

	func isActive(_ id: String) -> Bool {
		self.playingId == id || self.loadingId == id
	}

	/// Plays `tid`'s preview, or stops it when it is the one playing.
	func toggle(tid: String, server: NafynServer?) {
		if self.isActive(tid) {
			self.stop()
			return
		}
		guard let server, let url = Self.url(tid: tid, server: server) else { return }

		self.stop()
		// this device's own player only: one mirrored from another device (Unity) keeps playing there
		if !PlaybackSource.isRemote, PlayerEngine.shared.isPlaying {
			PlayerEngine.shared.togglePlay()
		}

		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
		try? AVAudioSession.sharedInstance().setActive(true)

		let item = AVPlayerItem(url: url)
		let player = AVPlayer(playerItem: item)
		self.player = player
		self.loadingId = tid

		self.statusObservation = item.observe(\.status) { [weak self] item, _ in
			Task { @MainActor in
				guard let self, self.loadingId == tid else { return }
				switch item.status {
					case .readyToPlay:
						self.loadingId = nil
						self.playingId = tid
					case .failed:
						self.unavailableIds.insert(tid)
						self.stop()
					default:
						break
				}
			}
		}
		self.observers = [
			NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.stop() }
			},
			NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.stop() }
			}
		]
		player.play()
	}

	func stop() {
		self.player?.pause()
		self.player = nil
		self.statusObservation = nil
		self.observers.forEach(NotificationCenter.default.removeObserver)
		self.observers = []
		self.playingId = nil
		self.loadingId = nil
	}

	/// `/api/v1/track/{tid}/preview?token=` on the signed-in server: a player can't set the Authorization header.
	private static func url(tid: String, server: NafynServer) -> URL? {
		let endpoint = Track.preview(tid: tid, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		return components.url
	}
}
