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

	private(set) var queue: [MediaRow] = []
	private(set) var currentIndex: Int = -1
	private(set) var isPlaying = false
	private(set) var currentTime: TimeInterval = 0
	private(set) var duration: TimeInterval = 0
	private(set) var lastError: String? = nil
	var isExpanded = false
	var repeatMode: RepeatMode = .off

	var currentTrack: MediaRow? {
		self.queue.indices.contains(self.currentIndex) ? self.queue[self.currentIndex] : nil
	}

	private var player: AVPlayer?
	private var didConfigureRemoteCommands = false
	private weak var server: NafynServer?
	private var timeObserver: Any?
	private var artworkCache: [String: MPMediaItemArtwork] = [:]
	private var itemObservers: [any NSObjectProtocol] = []

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

		#if canImport(UIKit) || canImport(AVFAudio)
		let audioSession = AVAudioSession.sharedInstance()
		try? audioSession.setCategory(.playback, mode: .default)
		if #available(iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
			audioSession.activate { _, _ in }
		} else {
			try? audioSession.setActive(true)
		}
		#endif

		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
			self.setupMediaSession()
		} else {
			self.setupRemoteCommandCenter()
		}
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
			player.play()
			self.isPlaying = true
			PlayTracker.shared.resumed()
		}
		self.updateNowPlayingInfo()
	}

	func next() {
		guard !self.queue.isEmpty else { return }

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

		if self.currentIndex - 1 >= 0 {
			self.currentIndex -= 1
			self.startCurrentItem()
		} else {
			self.seek(to: 0)
		}
	}

	func seek(to time: TimeInterval) {
		self.player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
		self.currentTime = time
		self.updateNowPlayingInfo()
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
			}
		}
	}

	func stop() {
		PlayTracker.shared.finished(completed: false)

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

		// On iOS 27+, `content`/`playbackSnapshot` above already become `nil` now that `currentTrack`
		// is `nil` — `MediaSession` observes that automatically and clears the system's Now Playing UI.
		// Only the legacy singleton needs to be told explicitly.
		if #unavailable(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0) {
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
		}
	}

	// MARK: - Item loading

	private func startCurrentItem() {
		guard let track = self.currentTrack, let url = self.streamURL(for: track) else { return }

		self.removeTimeObserver()

		let item = AVPlayerItem(url: url)
		if let player {
			player.replaceCurrentItem(with: item)
		} else {
			self.player = AVPlayer(playerItem: item)
		}

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

		self.player?.play()
		self.isPlaying = true

		PlayTracker.shared.began(track: track, source: self.playSource, playlistId: self.playPlaylistId)

		self.addTimeObserver()
		self.updateNowPlayingInfo()

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
		} else {
			self.next()
		}
	}

	private func streamURL(for track: MediaRow) -> URL? {
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
			guard let self else { return }
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
		]
		if let album = track.album {
			info[MPMediaItemPropertyAlbumTitle] = album
		}
		if let artwork = self.artworkCache[track.id] {
			info[MPMediaItemPropertyArtwork] = artwork
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = info
	}

	private func fetchArtwork(for track: MediaRow) {
		guard self.artworkCache[track.id] == nil, let url = track.highResCoverURL else { return }

		Task {
			guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
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
					let (data, _) = try await URLSession.shared.data(from: url)
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
