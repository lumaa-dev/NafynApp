// Made by Lumaa

import Foundation
import Safyn

/// Global singleton Nafyn Unity client, mirroring `PlayerEngine`'s role for local audio: one shared
/// socket that keeps this device's playback in sync with every other device the user is signed into.
///
/// Whenever `PlayerEngine` has something loaded, this device claims (or takes over) master and starts
/// publishing its state; incoming remote commands from other devices are executed straight on
/// `PlayerEngine`. When another device is master, this engine just mirrors its state (`remoteState`) so
/// UI elsewhere (e.g. a Settings row) can show what's playing and send it commands.
///
/// - Note: Deliberately does not touch `NowPlaying`/`MediaSession` — see `PlayerEngine`'s doc comment;
///   that integration is planned separately.
@Observable
final class UnityEngine {
	static let shared = UnityEngine()

	private(set) var isSettingEnabled = false
	private(set) var isConnected = false
	private(set) var isMaster = false
	private(set) var masterStatus: UnityMasterStatus = .empty
	private(set) var masterDeviceLabel: String? = nil
	private(set) var remoteState: UnityPlaybackState? = nil
	private(set) var lastError: String? = nil

	private var socket: NafynUnitySocket?
	private weak var server: NafynServer?
	private var isClaiming = false
	private var publishTimer: Timer?

	private init() {}

	// MARK: - Lifecycle

	/// Loads the user's Unity preference and connects if it's on. Call once per successful login,
	/// mirroring `PlayerEngine.configure(server:)`.
	func configure(server: NafynServer) {
		self.server = server
		Task { await self.refreshSettingAndConnect() }
	}

	private func refreshSettingAndConnect() async {
		guard let server else { return }
		let settings = try? await server.send(User.unitySettings) as UnitySettings
		self.isSettingEnabled = settings?.enabled ?? false
		guard self.isSettingEnabled else { return }
		self.connect()
	}

	/// Turns Nafyn Unity on/off account-wide, persisting the preference server-side and
	/// connecting/disconnecting this device's socket to match.
	func setEnabled(_ enabled: Bool) async {
		guard let server else { return }
		self.isSettingEnabled = enabled
		_ = try? await server.send(User.updateUnitySettings(enabled: enabled)) as UnitySettings
		if enabled {
			self.connect()
		} else {
			self.disconnect()
		}
	}

	func connect() {
		guard self.socket == nil, let server else { return }
		guard let socket = try? server.unitySocket() else { return }

		socket.onEvent = { [weak self] event in
			Task { @MainActor in self?.handle(event) }
		}
		socket.onClose = { [weak self] code, reason in
			Task { @MainActor in self?.handleClose(code: code, reason: reason) }
		}
		socket.onError = { [weak self] error in
			Task { @MainActor in self?.lastError = error.localizedDescription }
		}

		self.socket = socket
		socket.connect()
		self.isConnected = true
	}

	func disconnect() {
		self.socket?.disconnect()
		self.socket = nil
		self.isConnected = false
		self.isMaster = false
		self.remoteState = nil
		self.stopPublishTimer()
	}

	private func handleClose(code: Int, reason: String?) {
		self.isConnected = false
		self.isMaster = false
		self.stopPublishTimer()
		self.socket = nil

		switch code {
			case 4002: // Unity disabled server-side
				self.isSettingEnabled = false
			case 4008: // heartbeat timeout — safe to reconnect
				self.connect()
			default:
				self.lastError = reason
		}
	}

	// MARK: - Remote control (slave)

	/// Sends a command to whichever device is currently master. Answered with
	/// `UnityEvent.error(code: "no-master", ...)`, surfaced via `lastError`, if there is none.
	func sendCommand(_ command: UnityCommand) {
		self.socket?.send(command)
	}

	/// Pulls the remote master's current queue into this device's `PlayerEngine` and takes over as
	/// master, so playback continues locally from where the other device left off.
	func takeOverLocally() {
		guard let remoteState else { return }
		let tracks: [MediaRow] = remoteState.queue.compactMap { try? $0.decode(MediaRow.self) }
		guard tracks.indices.contains(remoteState.currentIndex) else { return }

		PlayerEngine.shared.play(tracks[remoteState.currentIndex], queue: tracks)
		PlayerEngine.shared.seek(to: remoteState.currentTime)
	}

	// MARK: - Local playback integration (master)

	/// Called by `PlayerEngine` after every state change. Claims/takes over master the first time this
	/// device has something loaded, and republishes state whenever it already is master.
	func playerDidChange() {
		guard self.socket != nil else { return }

		if PlayerEngine.shared.currentTrack != nil, !self.isMaster, !self.isClaiming {
			self.isClaiming = true
			if case .empty = self.masterStatus {
				self.socket?.claimMaster()
			} else {
				self.socket?.takeover()
			}
		}

		if self.isMaster {
			self.publishIfMaster()
		}
	}

	private func publishIfMaster() {
		guard self.isMaster, let socket = self.socket, let state = self.currentUnityState() else { return }
		socket.sendState(state)
	}

	private func currentUnityState() -> UnityPlaybackState? {
		let engine = PlayerEngine.shared
		guard !engine.queue.isEmpty else { return nil }

		let queueJSON: [JSONValue] = engine.queue.compactMap { track in
			guard let data = try? JSONEncoder().encode(track) else { return nil }
			return try? JSONDecoder().decode(JSONValue.self, from: data)
		}

		return UnityPlaybackState(
			queue: queueJSON,
			currentIndex: max(engine.currentIndex, 0),
			isPlaying: engine.isPlaying,
			isLoading: false,
			currentTime: engine.currentTime,
			duration: engine.duration,
			volume: engine.volume,
			muted: engine.isMuted,
			repeatMode: engine.repeatMode.wireValue
		)
	}

	private func startPublishTimer() {
		guard self.publishTimer == nil else { return }
		self.publishTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.publishIfMaster() }
		}
	}

	private func stopPublishTimer() {
		self.publishTimer?.invalidate()
		self.publishTimer = nil
	}

	private func execute(_ command: UnityCommand) {
		let engine = PlayerEngine.shared
		switch command {
			case .play:
				if !engine.isPlaying { engine.togglePlay() }
			case .togglePlay:
				engine.togglePlay()
			case .stop:
				engine.stop()
			case .next:
				engine.next()
			case .prev:
				engine.prev()
			case .seek(let seconds):
				engine.seek(to: seconds)
			case .setVolume(let value):
				engine.setVolume(value)
			case .toggleMute:
				engine.toggleMute()
			case .addToQueue(let track):
				if let media = try? track.decode(MediaRow.self) {
					engine.appendToQueue(media)
				}
			case .removeFromQueue(let index):
				engine.removeFromQueue(at: index)
			case .playFromQueue(let index):
				engine.playQueueIndex(index)
			case .cycleRepeat:
				engine.repeatMode = engine.repeatMode.next
			case .setRepeat(let mode):
				engine.repeatMode = RepeatMode(wireValue: mode)
			case .custom:
				break
		}
	}

	// MARK: - Event handling

	@MainActor
	private func handle(_ event: UnityEvent) {
		switch event {
			case .snapshot(let role, let state, let masterDeviceLabel, let masterStatus):
				self.isMaster = (role == "master")
				self.masterStatus = masterStatus
				self.masterDeviceLabel = masterDeviceLabel
				self.remoteState = self.isMaster ? nil : state
				self.isClaiming = false
				if self.isMaster {
					self.startPublishTimer()
				}
			case .claimGranted:
				self.isMaster = true
				self.isClaiming = false
				self.remoteState = nil
				self.startPublishTimer()
				self.publishIfMaster()
			case .claimRejected(let reason):
				self.isClaiming = false
				self.lastError = reason
			case .masterChanged(let youAreMaster, let deviceLabel):
				self.isMaster = youAreMaster
				self.masterDeviceLabel = deviceLabel
				self.isClaiming = false
				if youAreMaster {
					self.startPublishTimer()
					self.publishIfMaster()
				} else {
					self.stopPublishTimer()
				}
			case .state(let state):
				guard !self.isMaster else { return }
				self.remoteState = state
				self.masterStatus = .active
			case .command(let command):
				guard self.isMaster else { return }
				self.execute(command)
			case .masterDisconnected:
				self.masterStatus = .other("disconnected")
			case .masterCleared:
				self.masterStatus = .empty
				self.remoteState = nil
			case .error(let code, let message):
				self.lastError = "\(code): \(message)"
			case .unknown:
				break
		}
	}
}
