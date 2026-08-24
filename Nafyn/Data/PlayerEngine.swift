// Made by Lumaa

import Foundation
import AVFoundation
import MediaPlayer
import Safyn

/// The kind of media a fresh `play(_:queue:recordContext:)` call should record as recently-played.
/// Internal `next()`/`prev()` calls pass no context, since they're continuing an existing session
/// rather than starting a new "play this" action.
struct RecordContext {
	let type: RecentEntryKind
	let refId: String
}

enum RepeatMode {
	case off
	case queue
	case track
}

/// Global singleton audio engine, mirroring the web app's `usePlayer.ts`: one shared player that
/// survives navigation, streams via HTTP Range requests against `Library.stream`, and integrates with
/// the lock screen / Control Center through an `MPNowPlayingSession`.
@Observable
final class PlayerEngine: NSObject {
	static let shared = PlayerEngine()

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
	private var nowPlayingSession: MPNowPlayingSession?
	private weak var remoteCommandCenter: MPRemoteCommandCenter?
	private weak var server: NafynServer?
	private var timeObserver: Any?
	private var artworkCache: [String: MPMediaItemArtwork] = [:]

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

		// Remote command handling is attached to the player-specific Now Playing session.
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
		} else {
			player.play()
			self.isPlaying = true
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
		self.player?.pause()
		self.removeTimeObserver()
		self.player = nil
		self.isPlaying = false
		self.currentTime = 0
		self.duration = 0
		self.queue = []
		self.currentIndex = -1
		self.nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = nil
	}

	// MARK: - Item loading

	private func startCurrentItem() {
		guard let track = self.currentTrack, let url = self.streamURL(for: track) else { return }

		self.removeTimeObserver()

		let item = AVPlayerItem(url: url)
		if let player {
			player.replaceCurrentItem(with: item)
		} else {
			let player = AVPlayer(playerItem: item)
			self.player = player
			self.configureNowPlayingSession(for: player)
		}

		NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.itemDidPlayToEnd), name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
		NotificationCenter.default.removeObserver(self, name: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.itemFailedToPlay(_:)), name: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)

		self.currentTime = 0
		self.duration = 0
		self.lastError = nil

		self.player?.play()
		self.isPlaying = true

		self.addTimeObserver()
		self.updateNowPlayingInfo()
		self.fetchArtwork(for: track)
	}

	@objc private func itemFailedToPlay(_ notification: Notification) {
		let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
		self.lastError = error?.localizedDescription ?? "Playback failed"
		self.isPlaying = false
	}

	@objc private func itemDidPlayToEnd() {
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
		self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
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

	// MARK: - Remote commands / Now Playing info

	private func configureNowPlayingSession(for player: AVPlayer) {
		let session = MPNowPlayingSession(players: [player])
		session.automaticallyPublishesNowPlayingInfo = false
		self.nowPlayingSession = session
		self.setupRemoteCommandCenter(session.remoteCommandCenter)
		session.becomeActiveIfPossible()
	}

	private func setupRemoteCommandCenter(_ center: MPRemoteCommandCenter) {
		guard self.remoteCommandCenter !== center else { return }
		self.remoteCommandCenter = center

		center.playCommand.removeTarget(nil)
		center.pauseCommand.removeTarget(nil)
		center.nextTrackCommand.removeTarget(nil)
		center.previousTrackCommand.removeTarget(nil)
		center.changePlaybackPositionCommand.removeTarget(nil)

		center.playCommand.addTarget { [weak self] _ in
			guard let self, !self.isPlaying else { return .success }
			self.togglePlay()
			return .success
		}
		center.pauseCommand.addTarget { [weak self] _ in
			guard let self, self.isPlaying else { return .success }
			self.togglePlay()
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
		guard let track = self.currentTrack, let nowPlayingInfoCenter = self.nowPlayingSession?.nowPlayingInfoCenter else { return }

		var info: [String: Any] = [
			MPMediaItemPropertyTitle: track.title,
			MPMediaItemPropertyArtist: track.artistName,
			MPMediaItemPropertyPlaybackDuration: self.duration,
			MPNowPlayingInfoPropertyElapsedPlaybackTime: self.currentTime,
			MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
		]
		if let album = track.album {
			info[MPMediaItemPropertyAlbumTitle] = album
		}
		if let artwork = self.artworkCache[track.id] {
			info[MPMediaItemPropertyArtwork] = artwork
		}

		nowPlayingInfoCenter.nowPlayingInfo = info
	}

	private func fetchArtwork(for track: MediaRow) {
		guard self.artworkCache[track.id] == nil, let coverArt = track.coverArt, let url = URL(string: coverArt) else { return }

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
}
