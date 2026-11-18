// Made by Lumaa

import AppIntents
import Foundation
import Safyn

/// What an intent wants played, resolved to tracks, and the one place that starts them.
enum AudioPlayback {
	struct Queue {
		var tracks: [MediaRow]
		var context: RecordContext?
		/// What the queue is called when Siri answers ("Playing Dopamine Chamber").
		var title: String?
	}

	/// Queues prepared by the warm-up intent, started later by ID.
	@MainActor
	private static var prepared: [UUID: Queue] = [:]

	// MARK: Resolving

	static func queue(for item: AudioItem) async throws -> Queue {
		switch item {
			case .song(let song):
				return try await self.queue(song: song.id)
			case .album(let album):
				return try await self.queue(album: album.id)
			case .artist(let artist):
				// the ID is the name; reading `name` here makes the compiler expand the entity macros in a cycle
				return try await self.queue(artist: artist.id)
			case .playlist(let playlist):
				return try await self.queue(playlist: playlist.id)
		}
	}

	static func queue(artist name: String) async throws -> Queue {
		let tracks = try await LibraryCatalog.shared.tracks()
			.filter { LibrarySearch.normalize($0.artistName) == LibrarySearch.normalize(name) }
			.sorted { ($0.album ?? "", $0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.album ?? "", $1.discNumber ?? 1, $1.trackNumber ?? 0) }
		return Queue(tracks: tracks, context: nil, title: tracks.first?.artistName ?? name)
	}

	static func queue(song id: String) async throws -> Queue {
		let tracks = try await LibraryCatalog.shared.tracks().filter { $0.id == id }
		return Queue(tracks: tracks, context: RecordContext(type: .track, refId: id), title: tracks.first?.title)
	}

	static func queue(album id: String) async throws -> Queue {
		let tracks = try await LibraryCatalog.shared.tracks(ofAlbum: id)
		return Queue(tracks: tracks, context: RecordContext(type: .album, refId: id), title: tracks.first?.album)
	}

	static func queue(playlist id: String) async throws -> Queue {
		let server = try await AppSession.shared.resolveServer()
		var tracks: [MediaRow] = []
		var page = 1
		while true {
			let response = try await server.fetchPlaylistTracks(pid: id, page: page, limit: 100)
			tracks.append(contentsOf: response.items.map(\.media))
			guard response.hasMore else { break }
			page += 1
		}
		let title = try? await LibraryCatalog.shared.playlists().first { $0.id == id }?.title
		return Queue(tracks: tracks, context: RecordContext(type: .playlist, refId: id), title: title)
	}

	// MARK: Starting

	@MainActor
	static func prepare(_ queue: Queue) -> UUID {
		let id = UUID()
		self.prepared = [id: queue]
		return id
	}

	@MainActor
	static func prepared(_ id: UUID) -> Queue? {
		self.prepared[id]
	}

	/// What `start` did, for the sentence Siri says back.
	enum Outcome {
		case playing
		case shuffling
		case playingNext
		case addedToQueue
	}

	/// Starts `queue`, or (with `location`) adds it to the one that is playing.
	@MainActor
	@discardableResult
	static func start(_ queue: Queue, shuffle: Bool, repeatQueue: Bool, location: QueueInsertionLocation? = nil) throws -> Outcome {
		var tracks = queue.tracks
		guard !tracks.isEmpty else { throw AudioPlaybackError.nothingToPlay }

		if shuffle {
			tracks.shuffle()
		}

		if let location, PlayerEngine.shared.currentTrack != nil {
			switch location {
				case .next:
					PlayerEngine.shared.insertNext(tracks)
					return .playingNext
				case .tail:
					tracks.forEach { PlayerEngine.shared.appendToQueue($0) }
					return .addedToQueue
			}
		}

		PlaybackSource.play(tracks[0], queue: tracks, recordContext: queue.context)
		if repeatQueue, !PlaybackSource.isRemote {
			PlayerEngine.shared.repeatMode = .queue
		}
		return shuffle ? .shuffling : .playing
	}

	@MainActor
	@discardableResult
	static func start(_ queue: Queue, shuffle: Bool, repeatMode: RepeatOption) throws -> Outcome {
		let outcome = try self.start(queue, shuffle: shuffle, repeatQueue: false)
		guard !PlaybackSource.isRemote else { return outcome }
		switch repeatMode {
			case .off: PlayerEngine.shared.repeatMode = .off
			case .queue: PlayerEngine.shared.repeatMode = .queue
			case .track: PlayerEngine.shared.repeatMode = .track
		}
		return outcome
	}

	/// What Siri says once playback started: the reply that ends the request.
	static func dialog(_ outcome: Outcome, title: String?) -> IntentDialog {
		let name = title ?? String(localized: "dialog-fallback-your-music")
		return switch outcome {
			case .playing: "dialog-playing \(name)"
			case .shuffling: "dialog-shuffling \(name)"
			case .playingNext: "dialog-will-play-next \(name)"
			case .addedToQueue: "dialog-added-to-queue \(name)"
		}
	}
}

extension AudioPlayback {
	/// The owned tracks of these songs and of these albums, in that order, each once.
	static func tracks(songs: [String], albums: [String]) async throws -> [MediaRow] {
		guard !songs.isEmpty || !albums.isEmpty else { throw AudioPlaybackError.nothingToPlay }

		let library = try await LibraryCatalog.shared.tracks()
		let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

		var tracks = songs.compactMap { byId[$0] }
		for album in albums {
			tracks += try await LibraryCatalog.shared.tracks(ofAlbum: album)
		}

		var seen: Set<String> = []
		return tracks.filter { seen.insert($0.id).inserted }
	}

	/// The playlist's name, for Siri's answer.
	static func playlistTitle(_ id: String) async -> String {
		let rows = (try? await LibraryCatalog.shared.playlists()) ?? []
		return rows.first { $0.id == id }?.title ?? String(localized: "dialog-fallback-your-playlist")
	}

	/// Adds `tracks` to the playlist `id` (the server skips none: duplicates are the user's call).
	static func add(_ tracks: [MediaRow], toPlaylist id: String) async throws {
		guard !tracks.isEmpty else { throw AudioPlaybackError.nothingToPlay }
		let server = try await AppSession.shared.resolveServer()
		_ = try await server.sendRaw(Playlist.addTracks(pid: id, mediaIds: tracks.map(\.id)))
		await LibraryCatalog.shared.invalidatePlaylists()
	}
}

enum AudioPlaybackError: LocalizedError {
	case nothingToPlay
	case notInPlaylist
	case emptyName

	var errorDescription: String? {
		switch self {
			case .emptyName: String(localized: "playlist-name-required")
			case .nothingToPlay: String(localized: "nothing-to-play")
			case .notInPlaylist: String(localized: "song-not-in-playlist")
		}
	}
}

/// Repeat setting of the Shortcuts "Play" actions.
enum RepeatOption: String, AppEnum {
	case off
	case queue
	case track

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Repeat")

	static let caseDisplayRepresentations: [RepeatOption: DisplayRepresentation] = [
		.off: "Off",
		.queue: "All",
		.track: "One",
	]
}
