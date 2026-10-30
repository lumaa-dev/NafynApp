// Made by Lumaa

import AppIntents
import Foundation
import Safyn

/// What an intent wants played, resolved to tracks, and the one place that starts them.
enum AudioPlayback {
	struct Queue {
		var tracks: [MediaRow]
		var context: RecordContext?
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
				let tracks = try await LibraryCatalog.shared.tracks()
					.filter { $0.artistName.caseInsensitiveCompare(artist.id) == .orderedSame }
					.sorted { ($0.album ?? "", $0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.album ?? "", $1.discNumber ?? 1, $1.trackNumber ?? 0) }
				return Queue(tracks: tracks, context: nil)
			case .playlist(let playlist):
				return try await self.queue(playlist: playlist.id)
		}
	}

	static func queue(song id: String) async throws -> Queue {
		let tracks = try await LibraryCatalog.shared.tracks().filter { $0.id == id }
		return Queue(tracks: tracks, context: RecordContext(type: .track, refId: id))
	}

	static func queue(album id: String) async throws -> Queue {
		Queue(tracks: try await LibraryCatalog.shared.tracks(ofAlbum: id), context: RecordContext(type: .album, refId: id))
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
		return Queue(tracks: tracks, context: RecordContext(type: .playlist, refId: id))
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

	/// Starts `queue`, or (with `location`) adds it to the one that is playing.
	@MainActor
	static func start(_ queue: Queue, shuffle: Bool, repeatQueue: Bool, location: QueueInsertionLocation? = nil) throws {
		var tracks = queue.tracks
		guard !tracks.isEmpty else { throw AudioPlaybackError.nothingToPlay }

		if shuffle {
			tracks.shuffle()
		}

		if let location, PlayerEngine.shared.currentTrack != nil {
			switch location {
				case .next:
					PlayerEngine.shared.insertNext(tracks)
				case .tail:
					tracks.forEach { PlayerEngine.shared.appendToQueue($0) }
			}
			return
		}

		PlaybackSource.play(tracks[0], queue: tracks, recordContext: queue.context)
		if repeatQueue, !PlaybackSource.isRemote {
			PlayerEngine.shared.repeatMode = .queue
		}
	}

	@MainActor
	static func start(_ queue: Queue, shuffle: Bool, repeatMode: RepeatOption) throws {
		try self.start(queue, shuffle: shuffle, repeatQueue: false)
		guard !PlaybackSource.isRemote else { return }
		switch repeatMode {
			case .off: PlayerEngine.shared.repeatMode = .off
			case .queue: PlayerEngine.shared.repeatMode = .queue
			case .track: PlayerEngine.shared.repeatMode = .track
		}
	}
}

extension AudioPlayback {
	/// Adds `tracks` to the playlist `id` (the server skips none: duplicates are the user's call).
	static func add(_ tracks: [MediaRow], toPlaylist id: String) async throws {
		guard !tracks.isEmpty else { throw AudioPlaybackError.nothingToPlay }
		let server = try await AppSession.shared.resolveServer()
		_ = try await server.sendRaw(Playlist.addTracks(pid: id, mediaIds: tracks.map(\.id)))
		await LibraryCatalog.shared.invalidate()
	}
}

enum AudioPlaybackError: LocalizedError {
	case nothingToPlay
	case notInPlaylist

	var errorDescription: String? {
		switch self {
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
