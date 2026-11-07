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
/// Latency notes, because the server is only a relay and drops anything past 30 messages per second:
/// - the master publishes right after every change, but at most ~10 times a second (a trailing publish
///   covers the last change), and encodes the queue off the main thread, once per queue revision;
/// - a slave applies its own commands to `remoteState` straight away (`Optimistic`) instead of waiting for the
///   master's echo, and runs a local clock (`remoteTime`) between the master's once-a-second reports;
/// - `seek`/`setVolume` are throttled so dragging a slider can't flood the socket.
///
/// - Note: Deliberately does not touch `NowPlaying`/`MediaSession` — see `PlayerEngine`'s doc comment;
///   that integration is planned separately.
@Observable
final class UnityEngine {
	static let shared = UnityEngine()

	private(set) var isSettingEnabled = false
	/// `true` once the server's `snapshot` arrived, i.e. the socket is up and this device knows who is master.
	private(set) var isConnected = false
	private(set) var isMaster = false
	private(set) var masterStatus: UnityMasterStatus = .empty
	private(set) var masterDeviceLabel: String? = nil
	private(set) var remoteState: UnityPlaybackState? = nil {
		didSet {
			self.refreshRemoteQueue(old: oldValue)
			self.refreshRemoteClock()
		}
	}

	/// `remoteState`'s queue decoded to `MediaRow`s. Cached: the master republishes about once a second, and
	/// decoding the whole queue on every render would be wasted work while nothing in it changed.
	private(set) var remoteQueue: [MediaRow] = []

	/// The master's playback position, advanced locally between its reports so a slave's scrubber moves
	/// smoothly (and instantly after a seek) rather than stepping once a second.
	private(set) var remoteTime: TimeInterval = 0

	/// The master's current track, if there is one.
	var remoteTrack: MediaRow? {
		guard let state = self.remoteState, self.remoteQueue.indices.contains(state.currentIndex) else { return nil }
		return self.remoteQueue[state.currentIndex]
	}

	/// Another device is the active master, so playback actions started here belong on it, not on this device.
	var isControllingRemotely: Bool {
		self.isConnected && !self.isMaster && self.masterStatus == .active
	}

	private(set) var lastError: String? = nil

	@ObservationIgnored private var socket: NafynUnitySocket?
	@ObservationIgnored private weak var server: NafynServer?
	@ObservationIgnored private var isClaiming = false
	@ObservationIgnored private var publishTimer: Timer?
	@ObservationIgnored private var lastPublishAt = Date.distantPast
	@ObservationIgnored private var trailingPublish: Task<Void, Never>?
	@ObservationIgnored private let publisher = StatePublisher()

	@ObservationIgnored private var reconnectTask: Task<Void, Never>?
	@ObservationIgnored private var reconnectAttempts = 0
	@ObservationIgnored private var backgroundedAt: Date?
	/// This device was master when the socket dropped: if someone else holds the role on return, it must stop.
	@ObservationIgnored private var wasMasterBeforeDrop = false

	@ObservationIgnored private var lastCommandAt: [String: Date] = [:]
	@ObservationIgnored private var trailingCommands: [String: Task<Void, Never>] = [:]
	@ObservationIgnored private var optimistic = Optimistic()
	@ObservationIgnored private var remoteClock: Timer?
	@ObservationIgnored private var remoteTimeBase: TimeInterval = 0
	@ObservationIgnored private var remoteTimeAt = Date()

	/// Minimum gap between two state publishes (or two throttled commands); the server allows 30 messages per
	/// second per socket, this keeps well under it while still feeling immediate.
	private static let minSendInterval: TimeInterval = 0.1
	/// How long a slave trusts its own optimistic edit over what the master reports, to ride out reports that
	/// were already in flight when the command was sent.
	private static let optimisticWindow: TimeInterval = 1.5
	/// The server drops non-`state` messages above 64 KB; `play` carries a queue, so stay below that.
	private static let maxPlayPayloadBytes = 48_000
	/// Close codes after which retrying cannot succeed (bad/revoked token, Unity off, account gone).
	private static let refusedCloseCodes: Set<Int> = [4000, 4001, 4002, 4003, 4004]

	private init() {}

	// MARK: - Lifecycle

	/// Loads the user's Unity preference and connects if it's on. Call once per successful login,
	/// mirroring `PlayerEngine.configure(server:)`.
	func configure(server: NafynServer) {
		self.server = server
		Task { await self.refreshSettingAndConnect() }
	}

	@MainActor
	private func refreshSettingAndConnect() async {
		guard let server else { return }
		let settings = try? await server.send(User.unitySettings) as UnitySettings
		self.isSettingEnabled = settings?.enabled ?? false
		guard self.isSettingEnabled else { return }
		self.connect()
	}

	/// Turns Nafyn Unity on/off account-wide, persisting the preference server-side and
	/// connecting/disconnecting this device's socket to match.
	@MainActor
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

		// Callbacks are tied to the socket that raised them: a closed socket's late `onClose` must not tear
		// down the one that replaced it. `DispatchQueue.main` (not a `Task`) keeps events in arrival order.
		socket.onEvent = { [weak self, weak socket] event in
			DispatchQueue.main.async {
				guard let self, let socket else { return }
				MainActor.assumeIsolated { self.handle(event, from: socket) }
			}
		}
		socket.onClose = { [weak self, weak socket] code, reason in
			DispatchQueue.main.async {
				guard let self, let socket else { return }
				MainActor.assumeIsolated { self.handleClose(socket, code: code, reason: reason) }
			}
		}
		socket.onError = { [weak self, weak socket] error in
			DispatchQueue.main.async {
				guard let self, let socket else { return }
				MainActor.assumeIsolated { self.handleError(error, from: socket) }
			}
		}

		self.socket = socket
		socket.connect()
	}

	func disconnect() {
		self.reconnectTask?.cancel()
		self.reconnectTask = nil
		self.reconnectAttempts = 0

		let socket = self.socket
		self.socket = nil
		socket?.disconnect()

		self.resetConnectionState()
		self.wasMasterBeforeDrop = false
		self.masterStatus = .empty
		self.masterDeviceLabel = nil
	}

	/// Everything that only makes sense while a socket is up.
	private func resetConnectionState() {
		self.wasMasterBeforeDrop = self.wasMasterBeforeDrop || self.isMaster
		self.isConnected = false
		self.isMaster = false
		self.isClaiming = false
		self.remoteState = nil
		self.optimistic = Optimistic()
		self.stopPublishTimer()
		self.trailingPublish?.cancel()
		self.trailingPublish = nil
		self.trailingCommands.values.forEach { $0.cancel() }
		self.trailingCommands = [:]
	}

	private func refreshRemoteQueue(old: UnityPlaybackState?) {
		guard let state = self.remoteState else {
			self.remoteQueue = []
			return
		}
		guard old?.queue != state.queue else { return }
		self.remoteQueue = state.queue.compactMap { try? $0.decode(MediaRow.self) }
	}

	// MARK: - Connection health

	private func handleClose(_ closed: NafynUnitySocket, code: Int, reason: String?) {
		guard closed === self.socket else { return }
		self.socket = nil
		self.resetConnectionState()

		switch code {
			case 4002: // Unity disabled server-side
				self.isSettingEnabled = false
				self.lastError = reason
			case _ where Self.refusedCloseCodes.contains(code):
				self.lastError = reason
			default:
				self.lastError = reason
				self.scheduleReconnect(immediately: code == 4008)
		}
	}

	/// A transport failure (dropped Wi‑Fi, killed connection) can end the socket without a close frame, so
	/// `onClose` never fires. A server-side close surfaces here too, just before or after its close code, so
	/// the socket gets a moment for `handleClose` to run first; that keeps refused closes (Unity off, revoked
	/// session) from being retried.
	private func handleError(_ error: any Error, from failed: NafynUnitySocket) {
		guard failed === self.socket else { return }
		if error is DecodingError {
			self.lastError = error.localizedDescription
			return
		}

		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(300))
			guard let self, failed === self.socket else { return }
			failed.disconnect()
			self.socket = nil
			self.resetConnectionState()
			self.scheduleReconnect(immediately: false)
		}
	}

	/// Reconnects with a growing, jittered delay, like the web client does; the master role is held by the
	/// server for 30 s, and a same-session reconnect inside that window resumes as master.
	private func scheduleReconnect(immediately: Bool) {
		guard self.isSettingEnabled, self.reconnectTask == nil else { return }

		let base = min(3 * pow(2, Double(self.reconnectAttempts)), 60)
		let delay = immediately ? 0 : base * Double.random(in: 0.75...1.25)
		self.reconnectAttempts += 1

		self.reconnectTask = Task { @MainActor [weak self] in
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			guard !Task.isCancelled, let self else { return }
			self.reconnectTask = nil
			self.connect()
		}
	}

	func appDidEnterBackground() {
		self.backgroundedAt = Date()
	}

	/// A socket can die silently while the app is suspended. After a real stretch in the background, replace
	/// it, unless this device is the master and still playing (its audio keeps the app, and the socket, alive).
	func appDidBecomeActive() {
		defer { self.backgroundedAt = nil }
		guard self.isSettingEnabled else { return }

		guard self.socket != nil else {
			self.reconnectTask?.cancel()
			self.reconnectTask = nil
			self.reconnectAttempts = 0
			self.connect()
			return
		}

		guard let backgroundedAt, Date().timeIntervalSince(backgroundedAt) > 5 else { return }
		guard !(self.isMaster && PlayerEngine.shared.isPlaying) else { return }

		let stale = self.socket
		self.socket = nil
		stale?.disconnect()
		self.resetConnectionState()
		self.connect()
	}

	// MARK: - Remote control (slave)

	/// Sends a command to whichever device is currently master. Answered with
	/// `UnityEvent.error(code: "no-master", ...)`, surfaced via `lastError`, if there is none.
	///
	/// The effect on `remoteState` is applied immediately; `seek` and `setVolume` are throttled.
	func sendCommand(_ command: UnityCommand) {
		self.applyOptimistically(command)

		switch command {
			case .seek, .setVolume:
				self.sendThrottled(command)
			default:
				self.socket?.send(command)
		}
	}

	private func sendThrottled(_ command: UnityCommand) {
		let key = command.action
		self.trailingCommands[key]?.cancel()
		self.trailingCommands[key] = nil

		let elapsed = Date().timeIntervalSince(self.lastCommandAt[key] ?? .distantPast)
		if elapsed >= Self.minSendInterval {
			self.lastCommandAt[key] = Date()
			self.socket?.send(command)
			return
		}

		self.trailingCommands[key] = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Self.minSendInterval - elapsed))
			guard !Task.isCancelled, let self else { return }
			self.trailingCommands[key] = nil
			self.lastCommandAt[key] = Date()
			self.socket?.send(command)
		}
	}

	/// Plays `track` (in `queue`, when given) on the master device instead of this one.
	///
	/// Web masters understand `play(track, queue, context)`. Safyn parses every `play` action into a bare
	/// `UnityCommand.play` and drops its payload, so a native master could not read it; the same payload is
	/// therefore also sent as `playTrack`, which Safyn passes through as `.custom` and `execute(_:)` handles.
	/// A web master ignores the unknown action, and a native master finds itself already playing when the
	/// trailing bare `play` reaches it.
	func playOnMaster(_ track: MediaRow, queue: [MediaRow]?, recordContext: RecordContext?) {
		Task.detached(priority: .userInitiated) { [weak self] in
			guard let payload = Self.playPayload(track: track, queue: queue, recordContext: recordContext) else { return }
			await MainActor.run {
				guard let self, let socket = self.socket else { return }
				socket.send(.custom(action: "playTrack", payload: payload))
				socket.send(.custom(action: "play", payload: payload))
			}
		}
	}

	/// `[track, queue?, context?]`, with the queue cut down to a window around `track` that fits the server's
	/// message size cap.
	private static func playPayload(track: MediaRow, queue: [MediaRow]?, recordContext: RecordContext?) -> [JSONValue]? {
		guard let trackJSON = Self.json(of: track) else { return nil }
		var payload: [JSONValue] = [trackJSON.value]

		if let queue, let index = queue.firstIndex(where: { $0.id == track.id }) {
			var behind: [JSONValue] = [] // nearest first
			var ahead: [JSONValue] = []
			var bytes = trackJSON.bytes
			var next = index + 1
			var previous = index - 1
			var takeAhead = true

			// grow outward from the tapped track, alternating sides, until the budget or the queue runs out
			while next < queue.count || previous >= 0 {
				let useAhead = next < queue.count && (takeAhead || previous < 0)
				let source = queue[useAhead ? next : previous]
				guard let entry = Self.json(of: source), bytes + entry.bytes < Self.maxPlayPayloadBytes else { break }

				bytes += entry.bytes
				if useAhead {
					ahead.append(entry.value)
					next += 1
				} else {
					behind.append(entry.value)
					previous -= 1
				}
				takeAhead.toggle()
			}
			payload.append(.array(behind.reversed() + [trackJSON.value] + ahead))
		}

		if let recordContext {
			payload.append(.object([
				"type": .string(recordContext.type.rawValue),
				"refId": .string(recordContext.refId),
			]))
		}
		return payload
	}

	private static func json(of track: MediaRow) -> (value: JSONValue, bytes: Int)? {
		guard let data = try? JSONEncoder().encode(track),
		      let value = try? JSONDecoder().decode(JSONValue.self, from: data)
		else { return nil }
		return (value, data.count)
	}

	/// Pulls the remote master's current queue into this device's `PlayerEngine` and takes over as
	/// master, so playback continues locally from where the other device left off.
	func takeOverLocally() {
		guard let remoteState else { return }
		let tracks: [MediaRow] = remoteState.queue.compactMap { try? $0.decode(MediaRow.self) }
		guard tracks.indices.contains(remoteState.currentIndex) else { return }

		PlayerEngine.shared.play(tracks[remoteState.currentIndex], queue: tracks)
		PlayerEngine.shared.seek(to: self.remoteTime)
	}

	// MARK: - Slave-side prediction

	/// What a slave has asked for that the master hasn't confirmed yet. Reports already in flight when the
	/// command went out would otherwise flip the UI back for a moment.
	private struct Optimistic {
		var isPlaying: Bool?
		var muted: Bool?
		var volume: Double?
		var repeatMode: String?
		var seek: (time: TimeInterval, at: Date)?
		var expires = Date.distantPast

		var isEmpty: Bool {
			self.isPlaying == nil && self.muted == nil && self.volume == nil && self.repeatMode == nil && self.seek == nil
		}

		/// `state` with the unconfirmed edits laid over it; edits the master already reflects are dropped.
		mutating func apply(to state: UnityPlaybackState, now: Date = Date()) -> UnityPlaybackState {
			guard !self.isEmpty else { return state }
			guard now < self.expires else {
				self = Optimistic()
				return state
			}

			var state = state
			if let value = self.isPlaying {
				if state.isPlaying == value { self.isPlaying = nil } else { state.isPlaying = value }
			}
			if let value = self.muted {
				if state.muted == value { self.muted = nil } else { state.muted = value }
			}
			if let value = self.volume {
				if abs(state.volume - value) < 0.01 { self.volume = nil } else { state.volume = value }
			}
			if let value = self.repeatMode {
				if state.repeatMode == value { self.repeatMode = nil } else { state.repeatMode = value }
			}
			if let seek = self.seek {
				let expected = seek.time + (state.isPlaying ? now.timeIntervalSince(seek.at) : 0)
				if abs(state.currentTime - expected) < 1.5 { self.seek = nil } else { state.currentTime = expected }
			}
			return state
		}
	}

	private func applyOptimistically(_ command: UnityCommand) {
		guard var state = self.remoteState else { return }
		let now = Date()

		switch command {
			case .play:
				state.isPlaying = true
				self.optimistic.isPlaying = true
			case .togglePlay:
				state.isPlaying.toggle()
				self.optimistic.isPlaying = state.isPlaying
			case .seek(let seconds):
				state.currentTime = seconds
				self.optimistic.seek = (seconds, now)
			case .setVolume(let value):
				state.volume = value
				self.optimistic.volume = value
			case .toggleMute:
				state.muted.toggle()
				self.optimistic.muted = state.muted
			case .cycleRepeat:
				state.repeatMode = RepeatMode(wireValue: state.repeatMode).next.wireValue
				self.optimistic.repeatMode = state.repeatMode
			case .setRepeat(let mode):
				state.repeatMode = RepeatMode(wireValue: mode).wireValue
				self.optimistic.repeatMode = state.repeatMode
			default:
				return
		}

		self.optimistic.expires = now.addingTimeInterval(Self.optimisticWindow)
		self.remoteState = state
	}

	/// Re-bases the local clock on every report, and runs it only while the master is playing.
	private func refreshRemoteClock() {
		guard let state = self.remoteState else {
			self.remoteClock?.invalidate()
			self.remoteClock = nil
			self.remoteTime = 0
			return
		}

		self.remoteTimeBase = state.currentTime
		self.remoteTimeAt = Date()
		self.remoteTime = state.currentTime

		guard state.isPlaying else {
			self.remoteClock?.invalidate()
			self.remoteClock = nil
			return
		}
		guard self.remoteClock == nil else { return }

		self.remoteClock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self, let state = self.remoteState, state.isPlaying else { return }
				let estimate = self.remoteTimeBase + Date().timeIntervalSince(self.remoteTimeAt)
				self.remoteTime = state.duration > 0 ? min(estimate, state.duration) : estimate
			}
		}
	}

	// MARK: - Local playback integration (master)

	/// Called by `PlayerEngine` after every state change. Claims/takes over master the first time this
	/// device has something loaded, and republishes state whenever it already is master.
	func playerDidChange() {
		guard self.socket != nil, self.isConnected else { return }

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

	/// Publishes immediately when the last publish is old enough, otherwise once more shortly after, so a
	/// burst of changes (a dragged slider, a skipped queue) costs a few messages and still ends on the latest.
	private func publishIfMaster() {
		guard self.isMaster, self.socket != nil, self.trailingPublish == nil else { return }

		let elapsed = Date().timeIntervalSince(self.lastPublishAt)
		if elapsed >= Self.minSendInterval {
			self.publishNow()
			return
		}

		self.trailingPublish = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(Self.minSendInterval - elapsed))
			guard !Task.isCancelled, let self else { return }
			self.trailingPublish = nil
			self.publishNow()
		}
	}

	private func publishNow() {
		guard self.isMaster, let socket = self.socket else { return }
		let engine = PlayerEngine.shared
		guard !engine.queue.isEmpty else { return }

		self.lastPublishAt = Date()
		self.publisher.publish(
			to: socket,
			tracks: engine.queue,
			revision: engine.queueRevision,
			state: UnityPlaybackState(
				queue: [],
				currentIndex: max(engine.currentIndex, 0),
				isPlaying: engine.isPlaying,
				isLoading: false,
				currentTime: engine.currentTime,
				duration: engine.duration,
				volume: engine.volume,
				muted: engine.isMuted,
				repeatMode: engine.repeatMode.wireValue
			)
		)
	}

	private func startPublishTimer() {
		guard self.publishTimer == nil else { return }
		self.publishTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.publishIfMaster() }
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
			case .custom(let action, let payload):
				if action == "playTrack" {
					self.executePlayTrack(payload)
				} else if action == "shuffleQueue" {
					engine.shuffleUpcoming()
				}
		}
	}

	/// `playTrack` payload: `[track, queue?, { type, refId }?]`, see `playOnMaster(_:queue:recordContext:)`.
	private func executePlayTrack(_ payload: [JSONValue]) {
		guard let track = try? payload.first?.decode(MediaRow.self) else { return }

		var queue: [MediaRow]?
		if payload.indices.contains(1), case .array(let entries) = payload[1] {
			queue = entries.compactMap { try? $0.decode(MediaRow.self) }
		}

		var context: RecordContext?
		if payload.indices.contains(2), case .object(let object) = payload[2],
		   case .string(let rawType)? = object["type"], case .string(let refId)? = object["refId"],
		   let type = RecentEntryKind(rawValue: rawType) {
			context = RecordContext(type: type, refId: refId)
		}

		PlayerEngine.shared.play(track, queue: queue, recordContext: context)
	}

	// MARK: - Event handling

	@MainActor
	private func handle(_ event: UnityEvent, from socket: NafynUnitySocket) {
		guard socket === self.socket else { return }

		switch event {
			case .snapshot(let role, let state, let masterDeviceLabel, let masterStatus):
				self.isConnected = true
				self.reconnectAttempts = 0
				self.isClaiming = false
				self.isMaster = (role == "master")
				self.masterStatus = masterStatus
				self.masterDeviceLabel = masterDeviceLabel
				self.remoteState = self.isMaster ? nil : state

				if self.isMaster {
					self.startPublishTimer()
					self.publishIfMaster()
				} else if self.wasMasterBeforeDrop, masterStatus != .empty, PlayerEngine.shared.currentTrack != nil {
					// the role moved on while this device was offline
					PlayerEngine.shared.stop()
				} else if masterStatus == .empty {
					// something started playing here before the socket was up
					self.playerDidChange()
				}
				self.wasMasterBeforeDrop = false
			case .claimGranted:
				self.becomeMaster()
			case .claimRejected(let reason):
				// someone claimed first; this device is already playing, so it takes over instead
				self.isClaiming = false
				self.lastError = reason
				self.masterStatus = .active
				self.playerDidChange()
			case .masterChanged(let youAreMaster, let deviceLabel):
				self.masterDeviceLabel = deviceLabel
				self.masterStatus = .active
				self.isClaiming = false
				if youAreMaster {
					self.becomeMaster()
				} else {
					self.resignMaster()
				}
			case .state(let state):
				guard !self.isMaster else { return }
				self.masterStatus = .active
				self.remoteState = self.optimistic.apply(to: state)
			case .command(let command):
				guard self.isMaster else { return }
				self.execute(command)
			case .masterDisconnected:
				self.masterStatus = .other("grace")
			case .masterCleared:
				self.masterStatus = .empty
				self.masterDeviceLabel = nil
				self.remoteState = nil
			case .error(let code, let message):
				self.lastError = "\(code): \(message)"
			case .unknown:
				break
		}
	}

	private func becomeMaster() {
		self.isMaster = true
		self.isClaiming = false
		self.masterStatus = .active
		self.remoteState = nil
		self.optimistic = Optimistic()
		self.startPublishTimer()
		self.publishIfMaster()
	}

	/// Another device took over. Audio must only come out of the master, so this device stops (the web client
	/// pauses): without it two devices would play the same queue at once.
	private func resignMaster() {
		let wasMaster = self.isMaster
		self.isMaster = false
		self.stopPublishTimer()
		self.trailingPublish?.cancel()
		self.trailingPublish = nil

		if wasMaster, PlayerEngine.shared.currentTrack != nil {
			PlayerEngine.shared.stop()
		}
	}
}

/// Turns the master's `PlayerEngine` state into wire messages away from the main thread: encoding a whole
/// queue as JSON is the expensive part of a publish, so it happens on one serial queue and is cached until
/// the queue actually changes.
private final class StatePublisher: @unchecked Sendable {
	private let queue = DispatchQueue(label: "fr.lumaa.Nafyn.unity.publish", qos: .userInitiated)
	private var cachedRevision = -1
	private var cachedQueue: [JSONValue] = []

	/// `state.queue` is ignored and filled from `tracks`.
	func publish(to socket: NafynUnitySocket, tracks: [MediaRow], revision: Int, state: UnityPlaybackState) {
		self.queue.async {
			if revision != self.cachedRevision {
				self.cachedQueue = tracks.compactMap { track in
					guard let data = try? JSONEncoder().encode(track) else { return nil }
					return try? JSONDecoder().decode(JSONValue.self, from: data)
				}
				self.cachedRevision = revision
			}

			var state = state
			state.queue = self.cachedQueue
			socket.sendState(state)
		}
	}
}
