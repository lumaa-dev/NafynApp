// Made by Lumaa

import Foundation
import AVFoundation
import MediaPlayer
#if canImport(NowPlaying)
import NowPlaying
#endif
import Safyn

/// The kind of media a fresh `play(_:queue:recordContext:)` call should record as recently-played.
/// Internal `next()`/`prev()` calls pass no context, since they're continuing an existing session
/// rather than starting a new "play this" action.
struct RecordContext {
	let type: RecentEntryKind
	let refId: String
}

extension RecordContext {
	/// The `Insights` play-event source matching this record context.
	var playEventSource: PlayEventSource {
		switch self.type {
			case .track:
				return .track
			case .album:
				return .album
			case .playlist:
				return .playlist
		}
	}
}

enum RepeatMode {
	case off
	case queue
	case track

	/// Cycles off → queue → track → off, for a single toggle button.
	var next: RepeatMode {
		switch self {
			case .off: .queue
			case .queue: .track
			case .track: .off
		}
	}

	/// The Nafyn Unity wire value for this mode, as the web player names it (`"off" | "queue" | "track"`),
	/// used when publishing/receiving `UnityPlaybackState.repeatMode`/`UnityCommand.setRepeat`.
	var wireValue: String {
		switch self {
			case .off: "off"
			case .queue: "queue"
			case .track: "track"
		}
	}

	/// Also reads the `"all"`/`"one"` spelling Safyn's docs mention, in case a device sends it.
	init(wireValue: String) {
		switch wireValue {
			case "queue", "all": self = .queue
			case "track", "one": self = .track
			default: self = .off
		}
	}
}

/// Global singleton audio engine, mirroring the web app's `usePlayer.ts`: one shared player that
/// survives navigation, streams via HTTP Range requests against `Library.stream`, and integrates with
/// the lock screen / Control Center.
///
/// Two integration paths coexist, chosen once at `configure(server:)` and never mixed:
/// - iOS/tvOS/watchOS/visionOS 27+: the new `NowPlaying` framework (`MediaSession`), which observes
///   this class's `content`/`playbackSnapshot`/`commands` automatically — no manual push needed.
/// - Earlier OS versions: the classic `MPRemoteCommandCenter.shared()`/`MPNowPlayingInfoCenter.default()`
///   singletons, updated manually from `updateNowPlayingInfo()`.
@Observable
final class PlayerEngine: NSObject {
	static let shared = PlayerEngine()

	/// Stable identifier for the app's one Now Playing session (`MediaSessionRepresentable`'s
	/// `Identifiable` requirement on iOS 27+; unused, but harmless, on earlier OS versions).
	let id = "fr.lumaa.Nafyn.player"

	private(set) var queue: [MediaRow] = [] {
		didSet { self.queueRevision &+= 1 }
	}

	/// Bumped on every change to `queue`, so Nafyn Unity can re-encode the queue only when it changed.
	@ObservationIgnored private(set) var queueRevision = 0
	private(set) var currentIndex: Int = -1
	private(set) var isPlaying = false
	private(set) var currentTime: TimeInterval = 0
	private(set) var duration: TimeInterval = 0
	private(set) var lastError: String? = nil
	var isExpanded = false
	var repeatMode: RepeatMode = .off {
		didSet {
			self.mirrorRepeatShuffleToRemoteCommands()
			UnityEngine.shared.playerDidChange()
		}
	}
	private(set) var shuffleEnabled = false

	/// The songs played before the current one, oldest first, capped to ``Self/historyLimit``. Shown in the Queue
	/// panel (DESIGN.md "Queue Panel"): it never holds the current song nor a song twice in a row, so repeating a
	/// track (Repeat One) adds it once, and it is in memory only (gone when the app is closed).
	private(set) var history: [MediaRow] = []
	static let historyLimit = 50

	/// The song loaded last, which is the one that enters ``history`` when a different one takes over.
	@ObservationIgnored private var lastStartedTrack: MediaRow? = nil

	private(set) var volume: Double = 1
	private(set) var isMuted = false

	/// Queue indices in shuffled playback order, current track pinned first — only consulted by
	/// `next()`/`prev()` while `shuffleEnabled` is `true`. Recomputed on toggle and on any queue mutation
	/// while shuffle stays on, so it's always in sync with `queue`'s current contents.
	private var shuffledOrder: [Int] = []

	var currentTrack: MediaRow? {
		self.queue.indices.contains(self.currentIndex) ? self.queue[self.currentIndex] : nil
	}

	/// Indices into ``queue`` of what plays after the current song, in playing order (index `0` of this array is the
	/// next song). Never the current song nor an earlier one: those are the history's.
	var upcomingIndices: [Int] {
		if self.shuffleEnabled {
			guard let position = self.shuffledOrder.firstIndex(of: self.currentIndex) else { return [] }
			return Array(self.shuffledOrder.dropFirst(position + 1))
		}
		let start = self.currentIndex + 1
		return start < self.queue.count ? Array(start ..< self.queue.count) : []
	}

	/// Plays a song of the ``history`` right now, keeping it out of the way of what was queued: it takes the next
	/// spot in the queue and is started, so the queue carries on from where it was afterwards.
	func playFromHistory(_ track: MediaRow) {
		guard self.queue.indices.contains(self.currentIndex) else {
			self.play(track)
			return
		}
		self.insertNext([track])
		self.playQueueIndex(self.currentIndex + 1)
	}

	private func recordHistory(startingWith track: MediaRow) {
		defer { self.lastStartedTrack = track }
		guard let previous = self.lastStartedTrack, previous.id != track.id else { return }
		self.appendToHistory(previous)
	}

	private func appendToHistory(_ track: MediaRow) {
		// "Listening history" confirmed off (Settings → Privacy) means no history here either
		guard PlayTracker.shared.settings?.historyEnabled ?? true else {
			self.history = []
			return
		}
		guard self.history.last?.id != track.id else { return }
		self.history.append(track)
		if self.history.count > Self.historyLimit {
			self.history.removeFirst(self.history.count - Self.historyLimit)
		}
	}

	private var player: AVPlayer?
	private var didConfigureRemoteCommands = false
	private weak var server: NafynServer?
	private var timeObserver: Any?

	/// Seeks that haven't completed yet; while any are pending the time observer must not overwrite `currentTime`.
	@ObservationIgnored private var pendingSeeks = 0
	private var artworkCache: [String: MPMediaItemArtwork] = [:]
	private var itemObservers: [any NSObjectProtocol] = []
	private var interruptionObservers: [NotificationCenter.ObservationToken] = []

	/// Tracks whether the playback audio session is currently active, so `activateAudioSession()` only
	/// calls into `AVAudioSession` when there's actually a state change to make. Calling `activate(options:
	/// completionHandler:)`/`setActive(true)` again while already active is a harmless no-op as far as
	/// playback goes, but each call re-registers a completion handler with CoreAudio's session-core HAL
	/// dispatch table, and that's what was spamming the console with "cannot add handler to 0 from 0 -
	/// dropping" on every play/pause/resume.
	private var isAudioSessionActive = false

	/// Type-erased storage for `MediaSession<PlayerEngine>` (iOS 27+ only) — the concrete generic type
	/// can't be named in a stored property that must also compile on older OS versions, since
	/// `PlayerEngine`'s conformance to `MediaSessionRepresentable` is itself `@available`-gated below.
	private var mediaSessionBox: Any? = nil

	/// Where the current queue was started from, reported with every play event sent to `Insights`.
	private var playSource: PlayEventSource = .library

	/// The playlist the current queue was started from, if any, for the same reason.
	private var playPlaylistId: String? = nil

	private override init() {
		super.init()
	}

	func configure(server: NafynServer) {
		self.server = server

		self.activateAudioSession()
		self.observeAudioInterruptions()

		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
			self.setupMediaSession()
		} else {
			self.setupRemoteCommandCenter()
		}
	}

	// MARK: - Audio session

	/// Activates the playback audio session, and re-activates it after anything that may have torn it
	/// down (an interruption, a route loss).
	///
	/// A paused app whose audio session is inactive is not a Now Playing app as far as iOS is concerned,
	/// and the system drops its Now Playing entry — so the session is activated on every resume rather
	/// than only once at launch, and it is never deactivated on pause.
	private func activateAudioSession() {
		#if canImport(UIKit) || canImport(AVFAudio)
		guard !self.isAudioSessionActive else { return }
		self.isAudioSessionActive = true

		// `setCategory`/`setActive` can block for disk/IPC work under the hood; SessionCore warns if
		// they're called on the main thread while the session is active, so they run off it here.
		Task.detached(priority: .userInitiated) {
			let audioSession = AVAudioSession.sharedInstance()
			try? audioSession.setCategory(.playback, mode: .default)
			if #available(iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
				audioSession.activate { _, _ in }
			} else {
				try? audioSession.setActive(true)
			}
		}
		#endif
	}

	/// Keeps the Now Playing entry alive across interruptions (a call, another app taking the session).
	///
	/// An interruption pauses playback without any of this class's own pause paths running, so without
	/// this the reported state stays "playing" while nothing plays, and the entry is dropped when the
	/// interruption ends and the session isn't re-activated.
	private func observeAudioInterruptions() {
		#if canImport(AVFAudio)
		guard self.interruptionObservers.isEmpty else { return }

		let session = AVAudioSession.sharedInstance()

		// The system has already paused the player by the time this fires; mirror that so the Now
		// Playing entry shows a paused — not a stale playing — state.
		let inactiveToken = NotificationCenter.default.addObserver(
			of: session,
			for: AVAudioSession.DidBecomeInactiveMessage.self
		) { [weak self] _ in
			guard let self else { return }
			self.isAudioSessionActive = false
			guard self.isPlaying else { return }
			self.isPlaying = false
			PlayTracker.shared.paused()
			self.updateNowPlayingInfo()
		}

		let resumptionToken = NotificationCenter.default.addObserver(
			of: session,
			for: AVAudioSession.ResumptionRecommendationMessage.self
		) { [weak self] message in
			guard let self, message.recommendation == .shouldResume else { return }
			self.activateAudioSession()
			self.updateNowPlayingInfo()
			self.reassertNowPlayingSession()
		}

		self.interruptionObservers = [inactiveToken, resumptionToken]
		#endif
	}

	// MARK: - Playback control

	func play(_ track: MediaRow, queue: [MediaRow]? = nil, recordContext: RecordContext? = nil) {
		if let queue, let index = queue.firstIndex(where: { $0.id == track.id }) {
			self.queue = queue
			self.currentIndex = index
		} else {
			self.queue = [track]
			self.currentIndex = 0
		}

		self.playSource = recordContext.map(\.playEventSource) ?? .library
		self.playPlaylistId = recordContext.flatMap { $0.type == .playlist ? $0.refId : nil }

		if self.shuffleEnabled {
			self.reshuffle()
		}

		self.startCurrentItem()

		if let recordContext {
			self.recordRecentlyPlayed(recordContext)
		}
	}

	func togglePlay() {
		guard let player else { return }
		if self.isPlaying {
			player.pause()
			self.isPlaying = false
			PlayTracker.shared.paused()
		} else {
			// Resuming from a long pause can find the session deactivated (an interruption, another app
			// having taken it); activating first means `play()` isn't silently dropped.
			self.activateAudioSession()
			player.play()
			self.isPlaying = true
			PlayTracker.shared.resumed()
		}
		self.updateNowPlayingInfo()
		self.reassertNowPlayingSession()
		UnityEngine.shared.playerDidChange()
	}

	func next() {
		guard !self.queue.isEmpty else { return }

		if self.shuffleEnabled {
			guard let position = self.shuffledOrder.firstIndex(of: self.currentIndex) else { return }
			if position + 1 < self.shuffledOrder.count {
				self.currentIndex = self.shuffledOrder[position + 1]
			} else if self.repeatMode == .queue {
				self.currentIndex = self.shuffledOrder[0]
			} else {
				self.stop()
				return
			}
			self.startCurrentItem()
			return
		}

		if self.currentIndex + 1 < self.queue.count {
			self.currentIndex += 1
		} else if self.repeatMode == .queue {
			self.currentIndex = 0
		} else {
			self.stop()
			return
		}
		self.startCurrentItem()
	}

	func prev() {
		guard !self.queue.isEmpty else { return }

		if self.currentTime > 3 {
			self.seek(to: 0)
			return
		}

		if self.shuffleEnabled {
			guard let position = self.shuffledOrder.firstIndex(of: self.currentIndex) else { return }
			if position - 1 >= 0 {
				self.currentIndex = self.shuffledOrder[position - 1]
				self.startCurrentItem()
			} else {
				self.seek(to: 0)
			}
			return
		}

		if self.currentIndex - 1 >= 0 {
			self.currentIndex -= 1
			self.startCurrentItem()
		} else {
			self.seek(to: 0)
		}
	}

	/// Toggles shuffle, recomputing `shuffledOrder` when turning it on.
	func toggleShuffle() {
		self.shuffleEnabled.toggle()
		if self.shuffleEnabled {
			self.reshuffle()
		}
		self.mirrorRepeatShuffleToRemoteCommands()
		UnityEngine.shared.playerDidChange()
	}

	/// Reorders what plays after the current song, once, at random (the "Shuffle" of a Nafyn Unity web player);
	/// the current song, the songs before it and the history stay where they are.
	func shuffleUpcoming() {
		let start = self.currentIndex + 1
		guard self.queue.indices.contains(start) else { return }
		var upcoming = Array(self.queue[start...])
		upcoming.shuffle()
		self.queue.replaceSubrange(start..., with: upcoming)
		if self.shuffleEnabled {
			self.reshuffle()
		}
		UnityEngine.shared.playerDidChange()
	}

	/// Fisher-Yates-shuffles every queue index except the currently-playing one, which stays pinned first
	/// so enabling shuffle never jumps playback.
	private func reshuffle() {
		guard !self.queue.isEmpty else { self.shuffledOrder = []; return }
		var rest = Array(self.queue.indices).filter { $0 != self.currentIndex }
		rest.shuffle()
		self.shuffledOrder = self.queue.indices.contains(self.currentIndex) ? [self.currentIndex] + rest : rest
	}

	/// Reorders the queue, keeping the currently-playing track's identity (not its index) as the source of
	/// truth for `currentIndex` afterward — correct for any move, single or multi-item, without needing to
	/// track index shifts by hand. `Array.move(fromOffsets:toOffset:)` lives in SwiftUI, which this pure
	/// data-layer file deliberately doesn't import, so the same semantics are reimplemented manually here.
	func moveInQueue(from source: IndexSet, to destination: Int) {
		let playingId = self.currentTrack?.id

		let itemsToMove = source.map { self.queue[$0] }
		for index in source.sorted(by: >) {
			self.queue.remove(at: index)
		}
		let adjustedDestination = destination - source.filter { $0 < destination }.count
		self.queue.insert(contentsOf: itemsToMove, at: adjustedDestination)

		if let playingId, let newIndex = self.queue.firstIndex(where: { $0.id == playingId }) {
			self.currentIndex = newIndex
		}
		if self.shuffleEnabled {
			self.reshuffle()
		}
		UnityEngine.shared.playerDidChange()
	}

	func seek(to time: TimeInterval) {
		if let player {
			// the periodic observer reports the pre-seek position until the seek lands, which would drag
			// `currentTime` (and what Nafyn Unity publishes) back for a moment
			self.pendingSeeks += 1
			player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) { [weak self] _ in
				DispatchQueue.main.async {
					guard let self else { return }
					self.pendingSeeks = max(self.pendingSeeks - 1, 0)
					if self.pendingSeeks == 0 {
						self.currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : time
						UnityEngine.shared.playerDidChange()
					}
				}
			}
		}
		self.currentTime = time
		self.updateNowPlayingInfo()
		UnityEngine.shared.playerDidChange()
	}

	func removeFromQueue(at index: Int) {
		guard self.queue.indices.contains(index) else { return }
		self.queue.remove(at: index)

		if index < self.currentIndex {
			self.currentIndex -= 1
		} else if index == self.currentIndex {
			if self.queue.indices.contains(index) {
				self.startCurrentItem()
			} else {
				self.stop()
				return
			}
		}

		if self.shuffleEnabled {
			self.reshuffle()
		}

		UnityEngine.shared.playerDidChange()
	}

	/// Appends a track to the end of the queue, e.g. from a Nafyn Unity `addToQueue` remote command.
	func appendToQueue(_ track: MediaRow) {
		self.queue.append(track)
		if self.shuffleEnabled {
			self.reshuffle()
		}
		UnityEngine.shared.playerDidChange()
	}

	/// Queues `tracks` right after the current one ("Play Next"), without interrupting what is playing.
	func insertNext(_ tracks: [MediaRow]) {
		guard !tracks.isEmpty else { return }
		let position = self.queue.indices.contains(self.currentIndex) ? self.currentIndex + 1 : self.queue.count
		self.queue.insert(contentsOf: tracks, at: position)
		if self.shuffleEnabled {
			self.reshuffle()
		}
		UnityEngine.shared.playerDidChange()
	}

	/// Jumps directly to a queue index and plays it, e.g. from a Nafyn Unity `playFromQueue` remote command.
	func playQueueIndex(_ index: Int) {
		guard self.queue.indices.contains(index) else { return }
		self.currentIndex = index
		self.startCurrentItem()
	}

	/// Sets playback volume, `0...1`, e.g. from a Nafyn Unity `setVolume` remote command.
	func setVolume(_ value: Double) {
		self.volume = min(max(value, 0), 1)
		self.player?.volume = Float(self.volume)
		UnityEngine.shared.playerDidChange()
	}

	func toggleMute() {
		self.isMuted.toggle()
		self.player?.isMuted = self.isMuted
		UnityEngine.shared.playerDidChange()
	}

	func stop() {
		PlayTracker.shared.finished(completed: false)

		if let last = self.lastStartedTrack { self.appendToHistory(last) }
		self.lastStartedTrack = nil

		AudioReactivityEngine.shared.detach()
		self.player?.pause()
		self.removeTimeObserver()
		self.itemObservers.forEach(NotificationCenter.default.removeObserver)
		self.itemObservers = []
		self.player = nil
		self.isPlaying = false
		self.currentTime = 0
		self.duration = 0
		self.queue = []
		self.currentIndex = -1
		self.shuffledOrder = []

		// On iOS 27+, `content`/`playbackSnapshot` above already become `nil` now that `currentTrack`
		// is `nil` — `MediaSession` observes that automatically and clears the system's Now Playing UI.
		// Only the legacy singleton needs to be told explicitly.
		if #unavailable(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0) {
			// `playbackState` first: clearing `nowPlayingInfo` while the state still reads `.playing`
			// leaves the system with a playing app that has no item.
			MPNowPlayingInfoCenter.default().playbackState = .stopped
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
		}

		UnityEngine.shared.playerDidChange()
	}

	// MARK: - Item loading

	private func startCurrentItem() {
		guard let track = self.currentTrack, let url = self.streamURL(for: track) else { return }

		self.recordHistory(startingWith: track)
		self.removeTimeObserver()

		let item = AVPlayerItem(url: url)
		if let player {
			player.replaceCurrentItem(with: item)
		} else {
			self.player = AVPlayer(playerItem: item)
		}
		AudioReactivityEngine.shared.attach(to: item)

		// Block-based, delivered on the main queue: AVFoundation posts these from its own internal
		// queue, and both handlers touch main-actor state (`@Observable` playback properties, and
		// `PlayTracker`'s event session).
		self.itemObservers.forEach(NotificationCenter.default.removeObserver)
		self.itemObservers = [
			NotificationCenter.default.addObserver(
				forName: AVPlayerItem.didPlayToEndTimeNotification,
				object: item,
				queue: .main
			) { [weak self] _ in
				self?.itemDidPlayToEnd()
			},
			NotificationCenter.default.addObserver(
				forName: AVPlayerItem.failedToPlayToEndTimeNotification,
				object: item,
				queue: .main
			) { [weak self] notification in
				self?.itemFailedToPlay(notification)
			},
		]

		self.currentTime = 0
		self.duration = track.duration
		self.lastError = nil

		self.player?.volume = Float(self.volume)
		self.player?.isMuted = self.isMuted
		self.activateAudioSession()
		self.player?.play()
		self.isPlaying = true

		PlayTracker.shared.began(track: track, source: self.playSource, playlistId: self.playPlaylistId)

		self.addTimeObserver()
		self.updateNowPlayingInfo()
		UnityEngine.shared.playerDidChange()

		// On iOS 27+, `Artwork`'s provider closure (in the `content` conformance below) fetches
		// artwork lazily and on-demand — no need for the legacy path's manual prefetch/cache.
		if #unavailable(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0) {
			self.fetchArtwork(for: track)
		}
	}

	private func itemFailedToPlay(_ notification: Notification) {
		let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
		self.lastError = error?.localizedDescription ?? "Playback failed"
		self.isPlaying = false
	}

	private func itemDidPlayToEnd() {
		// Close the play event here rather than letting the next `startCurrentItem()`/`stop()` do it, so
		// this play is recorded as having reached the end of the file.
		PlayTracker.shared.finished(completed: true)

		if self.repeatMode == .track {
			self.seek(to: 0)
			self.player?.play()
			// Every time round is a listen of its own (repeat listening is counted in full, see the server's
			// insights rules): the session closed above is not reopened by anything else, since the item never
			// changes, so without this only the first play of a looped track ever reached the statistics.
			if let track = self.currentTrack {
				PlayTracker.shared.began(track: track, source: self.playSource, playlistId: self.playPlaylistId)
			}
		} else {
			self.next()
		}
	}

	private func streamURL(for track: MediaRow) -> URL? {
		// Offline-downloaded tracks play straight from disk — this is what makes airplane-mode
		// playback actually work, and it skips the network entirely even when it isn't needed.
		if let localURL = DownloadManager.shared.localFileURL(for: track.id) {
			return localURL
		}

		guard let server = self.server else { return nil }

		let endpoint = Library.stream(id: track.id, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		return components.url
	}

	private func recordRecentlyPlayed(_ context: RecordContext) {
		guard let server = self.server else { return }
		Task {
			_ = try? await server.send(Library.recordRecentlyPlayed(type: context.type, refId: context.refId)) as RecordedResponse
		}
	}

	// MARK: - Time observation

	private func addTimeObserver() {
		guard let player else { return }
		// 0.1s (rather than the usual 0.5s) so `currentTime`-driven UI (the scrubber, syllable-level
		// lyrics highlighting) tracks playback smoothly instead of visibly stepping.
		self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
			guard let self, self.pendingSeeks == 0 else { return }
			self.currentTime = time.seconds.isFinite ? time.seconds : 0
			if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
				self.duration = itemDuration
			}
		}
	}

	private func removeTimeObserver() {
		if let timeObserver, let player {
			player.removeTimeObserver(timeObserver)
		}
		self.timeObserver = nil
	}

	// MARK: - Remote command actions (shared by both integration paths)

	private func remotePlay() {
		guard !self.isPlaying else { return }
		self.togglePlay()
	}

	private func remotePause() {
		guard self.isPlaying else { return }
		self.togglePlay()
	}

	// MARK: - Legacy path (< iOS 27): MPRemoteCommandCenter / MPNowPlayingInfoCenter

	private func setupRemoteCommandCenter() {
		guard !self.didConfigureRemoteCommands else { return }
		self.didConfigureRemoteCommands = true

		let center = MPRemoteCommandCenter.shared()
		center.playCommand.isEnabled = true
		center.pauseCommand.isEnabled = true
		center.togglePlayPauseCommand.isEnabled = true
		center.nextTrackCommand.isEnabled = true
		center.previousTrackCommand.isEnabled = true
		center.changePlaybackPositionCommand.isEnabled = true
		center.changeRepeatModeCommand.isEnabled = true
		center.changeShuffleModeCommand.isEnabled = true

		center.playCommand.addTarget { [weak self] _ in
			self?.remotePlay()
			return .success
		}
		center.pauseCommand.addTarget { [weak self] _ in
			self?.remotePause()
			return .success
		}
		center.togglePlayPauseCommand.addTarget { [weak self] _ in
			self?.togglePlay()
			return .success
		}
		center.nextTrackCommand.addTarget { [weak self] _ in
			self?.next()
			return .success
		}
		center.previousTrackCommand.addTarget { [weak self] _ in
			self?.prev()
			return .success
		}
		center.changePlaybackPositionCommand.addTarget { [weak self] event in
			guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
			self?.seek(to: event.positionTime)
			return .success
		}
		center.changeRepeatModeCommand.addTarget { [weak self] event in
			guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
			switch event.repeatType {
				case .off: self?.repeatMode = .off
				case .all: self?.repeatMode = .queue
				case .one: self?.repeatMode = .track
				@unknown default: break
			}
			return .success
		}
		center.changeShuffleModeCommand.addTarget { [weak self] event in
			guard let event = event as? MPChangeShuffleModeCommandEvent, let self else { return .commandFailed }
			if (event.shuffleType != .off) != self.shuffleEnabled {
				self.toggleShuffle()
			}
			return .success
		}

		self.mirrorRepeatShuffleToRemoteCommands()
	}

	/// Mirrors `repeatMode`/`shuffleEnabled` into the legacy command center so Control Center/lock-screen
	/// glyphs reflect in-app state (and app-initiated changes don't look stale remotely). No-op on iOS 27+,
	/// where `MediaSession` doesn't expose repeat/shuffle commands to mirror into.
	private func mirrorRepeatShuffleToRemoteCommands() {
		guard #unavailable(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0) else { return }
		guard self.didConfigureRemoteCommands else { return }

		let center = MPRemoteCommandCenter.shared()
		center.changeRepeatModeCommand.currentRepeatType = switch self.repeatMode {
			case .off: .off
			case .queue: .all
			case .track: .one
		}
		center.changeShuffleModeCommand.currentShuffleType = self.shuffleEnabled ? .items : .off
	}

	private func updateNowPlayingInfo() {
		// `MediaSession` (iOS 27+) observes `content`/`playbackSnapshot` on its own; pushing to the
		// legacy singleton too would just be redundant (and could momentarily race with it).
		guard #unavailable(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0) else { return }
		guard let track = self.currentTrack else { return }

		var info: [String: Any] = [
			MPMediaItemPropertyTitle: track.title,
			MPMediaItemPropertyArtist: track.artistName,
			MPMediaItemPropertyPlaybackDuration: self.duration,
			MPNowPlayingInfoPropertyElapsedPlaybackTime: self.currentTime,
			// Pausing only ever changes the rate to 0 here — title/artist/artwork/duration stay
			// populated, so the system's Now Playing surface stays up with a paused state instead of
			// disappearing.
			MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
			MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
		]
		if let album = track.album {
			info[MPMediaItemPropertyAlbumTitle] = album
		}
		if let artwork = self.artworkCache[track.id] {
			info[MPMediaItemPropertyArtwork] = artwork
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = info

		// iOS drops a Now Playing entry whose owner never reports a state — a rate of 0 alone reads as
		// "stopped playing" and takes the entry with it. `.paused` is what keeps the item on screen,
		// with its controls live, while nothing is coming out of the speaker.
		MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
	}

	/// Cover bytes for Now Playing artwork.
	fileprivate static func artworkData(from url: URL) async -> Data? {
		await CoverArtLoader.shared.contents(of: url)
	}

	private func fetchArtwork(for track: MediaRow) {
		guard self.artworkCache[track.id] == nil, let url = track.highResCoverURL else { return }

		Task {
			guard let data = await Self.artworkData(from: url) else { return }
			#if canImport(UIKit)
			guard let image = UIImage(data: data) else { return }
			let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
			#elseif canImport(AppKit)
			guard let image = NSImage(data: data) else { return }
			let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
			#else
			return
			#endif

			await MainActor.run {
				self.artworkCache[track.id] = artwork
				if self.currentTrack?.id == track.id {
					self.updateNowPlayingInfo()
				}
			}
		}
	}

	// MARK: - iOS 27+ path: NowPlaying framework (MediaSession)

	/// Re-requests application-primary status when the session has lost it.
	///
	/// Pausing can cost the app its primary session on iOS 27 betas, which removes the Now Playing entry
	/// outright instead of leaving it paused and resumable. Asking for it back after every pause/resume
	/// (and after an interruption) restores the entry; it's a no-op whenever the session is still
	/// primary, which is the case on a healthy system.
	private func reassertNowPlayingSession() {
		#if canImport(NowPlaying)
		guard #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) else { return }
		guard let session = self.mediaSessionBox as? MediaSession<PlayerEngine> else { return }
		guard self.currentTrack != nil else { return }

		Task { @MainActor in
			guard !session.isApplicationPrimary, session.canBecomeApplicationPrimary else { return }
			try? await session.requestToBecomeApplicationPrimary()
		}
		#endif
	}

	@available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
	private func setupMediaSession() {
		#if canImport(NowPlaying)
		guard self.mediaSessionBox == nil else { return }
		let session = MediaSession(self)
		self.mediaSessionBox = session
		Task {
			try? await session.requestToBecomeApplicationPrimary()
		}
		#endif
	}
}

#if canImport(NowPlaying)
@available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension PlayerEngine: MediaSessionRepresentable {
	var content: (any MediaContentRepresentable)? {
		guard let track = self.currentTrack else { return nil }

		return MusicContent(
			id: track.id,
			songTitle: track.title,
			artistName: track.artistName,
			albumName: track.album ?? "",
			type: .audio,
			duration: .finite(max(self.duration, track.duration)),
			artwork: track.highResCoverURL.map { url in
				Artwork(id: track.id) { _ in
					guard let data = await Self.artworkData(from: url) else { throw URLError(.cannotLoadFromNetwork) }
					return try ArtworkRepresentation(data: data)
				}
			}
		)
	}

	var playbackSnapshot: MediaPlaybackSnapshot? {
		guard self.currentTrack != nil else { return nil }
		let state: MediaPlaybackSnapshot.PlaybackState = self.isPlaying ? .playing(rate: 1.0) : .paused
		return MediaPlaybackSnapshot(state: state, defaultPlaybackRate: 1.0, elapsedTime: self.currentTime, timestamp: .now)
	}

	// `NowPlaying`/`MediaSession` (this framework) has no repeat/shuffle `MediaCommand` case as of iOS 27 —
	// unlike the legacy path below, repeat/shuffle here are in-app-only controls with no lock-screen/
	// Control Center remote-command counterpart to wire up.
	var commands: [MediaCommand] {
		[
			.play { [weak self] in self?.remotePlay() },
			.pause { [weak self] in self?.remotePause() },
			.togglePlayPause { [weak self] in self?.togglePlay() },
			.next { [weak self] in self?.next() },
			.previous { [weak self] in self?.prev() },
			.seekToPosition { [weak self] time in self?.seek(to: time) },
		]
	}
}
#endif
