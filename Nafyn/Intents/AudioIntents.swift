// Made by Lumaa

import AppIntents
import Foundation
import MediaIntents
import Safyn

// The `.audio` schema intents: what Siri with Apple Intelligence runs for "Play …" and "Add this to my
// playlist". They share their playback code with the Shortcuts actions (see `ShortcutIntents.swift`).

@AppIntent(schema: .audio.playAudio)
struct PlayAudioIntent: AudioStartingIntent {
	var audioEntity: AudioItem
	var playbackAttributes: Set<PlaybackAttributes>
	var warmupAudioQueueResult: WarmupAudioQueueResult?
	var queueLocation: QueueInsertionLocation?

	@MainActor
	func perform() async throws -> some IntentResult {
		let queue: AudioPlayback.Queue
		if let id = self.warmupAudioQueueResult?.queueId, let prepared = AudioPlayback.prepared(id) {
			queue = prepared
		} else {
			queue = try await AudioPlayback.queue(for: self.audioEntity)
		}

		try AudioPlayback.start(
			queue,
			shuffle: self.playbackAttributes.contains(.shuffle),
			repeatQueue: self.playbackAttributes.contains(.repeat),
			location: self.queueLocation
		)
		return .result()
	}
}

@AppIntent(schema: .audio.warmupAudioQueue)
struct WarmupAudioQueueIntent {
	var audioEntity: AudioItem
	var playbackAttributes: Set<PlaybackAttributes>

	@MainActor
	func perform() async throws -> some ReturnsValue<WarmupAudioQueueResult> {
		var queue = try await AudioPlayback.queue(for: self.audioEntity)
		if self.playbackAttributes.contains(.shuffle) {
			queue.tracks.shuffle()
		}
		return .result(value: WarmupAudioQueueResult(queueId: AudioPlayback.prepare(queue)))
	}
}

@AppIntent(schema: .audio.addToPlaylist)
struct AddAudioToPlaylistIntent {
	var audioEntity: AudioItem
	var playlist: PlaylistEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		let queue = try await AudioPlayback.queue(for: self.audioEntity)
		try await AudioPlayback.add(queue.tracks, toPlaylist: self.playlist.id)
		return .result()
	}
}

/// Siri hands over what the person asked for ("play Dopamine Chamber"); this finds it in the library.
struct AudioSearchQuery: IntentValueQuery {
	func values(for search: AudioSearch) async throws -> [AudioItem] {
		switch search.criteria {
			case .searchQuery(let text):
				return try await Self.items(matching: text)
			case .unspecified:
				// "Play some music": the newest albums
				return try await LibraryCatalog.shared.albums()
					.sorted { $0.addedAt > $1.addedAt }
					.prefix(1)
					.map { AudioItem.album(AlbumEntity(row: $0)) }
			case .url:
				return []
		}
	}

	/// Songs, albums, artists and playlists whose name contains `text`, exact matches first.
	private static func items(matching text: String) async throws -> [AudioItem] {
		let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return [] }

		let tracks = try await LibraryCatalog.shared.tracks()
		let albums = try await LibraryCatalog.shared.albums()
		let playlists = (try? await LibraryCatalog.shared.playlists()) ?? []

		func rank(_ name: String) -> Int {
			if name.caseInsensitiveCompare(query) == .orderedSame { return 0 }
			if name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 1 }
			return 2
		}

		var scored: [(rank: Int, item: AudioItem)] = []

		for album in albums where rank(album.title) < 2 {
			scored.append((rank(album.title), .album(AlbumEntity(row: album))))
		}
		for artist in Set(tracks.map(\.artistName)) where rank(artist) < 2 {
			scored.append((rank(artist), .artist(ArtistEntity(name: artist))))
		}
		for track in tracks where rank(track.title) < 2 {
			scored.append((rank(track.title), .song(SongEntity(row: track))))
		}
		for playlist in playlists where rank(playlist.title) < 2 {
			let entity = await MainActor.run { PlaylistEntity(row: playlist) }
			scored.append((rank(playlist.title), .playlist(entity)))
		}

		return scored.sorted { $0.rank < $1.rank }.prefix(10).map(\.item)
	}
}
