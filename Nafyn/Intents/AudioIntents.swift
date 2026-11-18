// Made by Lumaa

import AppIntents
import Foundation
import MediaIntents
import Safyn

// The `.audio` schema intents: what Siri with Apple Intelligence runs for "Play …" and "Add this to my
// playlist". They share their playback code with the Shortcuts actions (see `ShortcutIntents.swift`).

@AppIntent(schema: .audio.playAudio)
struct PlayAudioIntent: AudioPlaybackIntent {
	var audioEntity: AudioItem
	var playbackAttributes: Set<PlaybackAttributes>
	var warmupAudioQueueResult: WarmupAudioQueueResult?
	var queueLocation: QueueInsertionLocation?

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let queue: AudioPlayback.Queue
		if let id = self.warmupAudioQueueResult?.queueId, let prepared = AudioPlayback.prepared(id) {
			queue = prepared
		} else {
			queue = try await AudioPlayback.queue(for: self.audioEntity)
		}

		let shuffle = self.playbackAttributes.contains(.shuffle)
		let outcome = try AudioPlayback.start(
			queue,
			shuffle: shuffle,
			repeatQueue: self.playbackAttributes.contains(.repeat),
			location: self.queueLocation
		)
		// without a spoken answer Siri keeps listening until the person dismisses it
		return .result(dialog: AudioPlayback.dialog(outcome, title: queue.title))
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
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let queue = try await AudioPlayback.queue(for: self.audioEntity)
		try await AudioPlayback.add(queue.tracks, toPlaylist: self.playlist.id)
		let name = await AudioPlayback.playlistTitle(self.playlist.id)
		return .result(dialog: "dialog-added-to-playlist \(name)")
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
			@unknown default:
				return []
		}
	}

	/// Songs, albums, artists and playlists that match `text`, best first. A whole-name match of an album
	/// or artist beats a song that merely contains the words.
	private static func items(matching text: String) async throws -> [AudioItem] {
		async let tracks = LibraryCatalog.shared.tracks()
		async let albums = LibraryCatalog.shared.albums()
		async let playlists = LibraryCatalog.shared.playlists()

		let allTracks = try await tracks
		let allAlbums = try await albums
		let allPlaylists = (try? await playlists) ?? []

		var scored: [(score: Int, kind: Int, item: AudioItem)] = []

		for match in LibrarySearch.albums(allAlbums, matching: text).prefix(10) {
			scored.append((match.score, 1, .album(AlbumEntity(row: match.row))))
		}
		for match in LibrarySearch.artists(LibrarySearch.artistNames(in: allTracks), matching: text).prefix(10) {
			scored.append((match.score, 2, .artist(ArtistEntity(name: match.row))))
		}
		for match in LibrarySearch.tracks(allTracks, matching: text).prefix(10) {
			scored.append((match.score, 0, .song(SongEntity(row: match.row))))
		}
		for match in LibrarySearch.playlists(allPlaylists, matching: text).prefix(5) {
			let entity = await MainActor.run { PlaylistEntity(row: match.row) }
			scored.append((match.score, 3, .playlist(entity)))
		}

		// stable: equal scores keep the order above (songs, albums, artists, playlists)
		return scored
			.enumerated()
			.sorted { ($0.element.score, $0.element.kind, $0.offset) < ($1.element.score, $1.element.kind, $1.offset) }
			.prefix(10)
			.map(\.element.item)
	}
}
