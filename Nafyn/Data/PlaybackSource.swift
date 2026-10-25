// Made by Lumaa

import Foundation
import Safyn

/// What the player UI (mini bar, full player, queue) should show and control: this device's own
/// `PlayerEngine`, or — when another device is the Nafyn Unity master — that device's playback, mirrored
/// here as if this device were playing it. Audio only ever comes out of the master; every action in remote
/// mode is sent to it as a Unity slave command.
///
/// Stateless on purpose: it only reads `@Observable` singletons, so any view using it re-renders when the
/// underlying engine changes.
enum PlaybackSource {
	/// Another device is playing and this one is only mirroring/controlling it.
	static var isRemote: Bool {
		let unity = UnityEngine.shared
		return !unity.isMaster && unity.remoteTrack != nil
	}

	/// The device the audio comes out of, when remote.
	static var hostLabel: String? {
		self.isRemote ? UnityEngine.shared.masterDeviceLabel : nil
	}

	static var track: MediaRow? {
		self.isRemote ? UnityEngine.shared.remoteTrack : PlayerEngine.shared.currentTrack
	}

	static var hasTrack: Bool {
		self.track != nil
	}

	static var isPlaying: Bool {
		self.isRemote ? (UnityEngine.shared.remoteState?.isPlaying ?? false) : PlayerEngine.shared.isPlaying
	}

	static var currentTime: TimeInterval {
		self.isRemote ? UnityEngine.shared.remoteTime : PlayerEngine.shared.currentTime
	}

	static var duration: TimeInterval {
		self.isRemote ? (UnityEngine.shared.remoteState?.duration ?? 0) : PlayerEngine.shared.duration
	}

	static var queue: [MediaRow] {
		self.isRemote ? UnityEngine.shared.remoteQueue : PlayerEngine.shared.queue
	}

	static var currentIndex: Int {
		self.isRemote ? (UnityEngine.shared.remoteState?.currentIndex ?? -1) : PlayerEngine.shared.currentIndex
	}

	// MARK: - Transport

	/// Starts `track` (in `queue`, when given). While another device is the Unity master the track plays
	/// there, not on this device; otherwise it plays locally.
	static func play(_ track: MediaRow, queue: [MediaRow]? = nil, recordContext: RecordContext? = nil) {
		if UnityEngine.shared.isControllingRemotely {
			UnityEngine.shared.playOnMaster(track, queue: queue, recordContext: recordContext)
		} else {
			PlayerEngine.shared.play(track, queue: queue, recordContext: recordContext)
		}
	}

	static func togglePlay() {
		self.isRemote ? UnityEngine.shared.sendCommand(.togglePlay) : PlayerEngine.shared.togglePlay()
	}

	static func next() {
		self.isRemote ? UnityEngine.shared.sendCommand(.next) : PlayerEngine.shared.next()
	}

	static func prev() {
		self.isRemote ? UnityEngine.shared.sendCommand(.prev) : PlayerEngine.shared.prev()
	}

	static func seek(to time: TimeInterval) {
		self.isRemote ? UnityEngine.shared.sendCommand(.seek(time)) : PlayerEngine.shared.seek(to: time)
	}
}
