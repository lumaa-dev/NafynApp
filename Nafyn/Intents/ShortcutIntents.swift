// Made by Lumaa

import AppIntents
import Foundation
import Safyn
import UIKit
import UniformTypeIdentifiers

// Shortcuts actions. Everything they return is a Nafyn entity (`SongEntity`, `AlbumEntity`,
// `PlaylistEntity`) so a shortcut works with real objects (title, artist, duration, date added, …)
// instead of text. Like every intent here they only ever see the signed-in user's own library.

// MARK: - Fetching

struct FindLibraryTracksIntent: AppIntent {
	static let title: LocalizedStringResource = "Find Library Tracks"
	static let description = IntentDescription("Finds tracks in your Nafyn library, filtered and sorted.", categoryName: "Library")

	@Parameter(title: "Search")
	var searchText: String?

	@Parameter(title: "Artist")
	var artist: String?

	@Parameter(title: "Album")
	var album: String?

	@Parameter(title: "Added After")
	var addedAfter: Date?

	@Parameter(title: "Added Before")
	var addedBefore: Date?

	@Parameter(title: "Downloaded Only", default: false)
	var downloadedOnly: Bool

	@Parameter(title: "Sort By", default: .dateAdded)
	var sortBy: TrackSortOption

	@Parameter(title: "Ascending", default: false)
	var ascending: Bool

	@Parameter(title: "Limit", default: 25)
	var limit: Int?

	static var parameterSummary: some ParameterSummary {
		Summary("Find tracks sorted by \(\.$sortBy)") {
			\.$searchText
			\.$artist
			\.$album
			\.$addedAfter
			\.$addedBefore
			\.$downloadedOnly
			\.$ascending
			\.$limit
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<[SongEntity]> {
		var tracks = try await LibraryCatalog.shared.tracks()

		if let text = self.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
			tracks = tracks.filter {
				$0.title.localizedCaseInsensitiveContains(text)
					|| $0.artistName.localizedCaseInsensitiveContains(text)
					|| ($0.album?.localizedCaseInsensitiveContains(text) ?? false)
			}
		}
		if let artist = self.artist, !artist.isEmpty {
			tracks = tracks.filter { $0.artistName.localizedCaseInsensitiveContains(artist) }
		}
		if let album = self.album, !album.isEmpty {
			tracks = tracks.filter { $0.album?.localizedCaseInsensitiveContains(album) ?? false }
		}
		if let addedAfter = self.addedAfter {
			tracks = tracks.filter { $0.addedAtDate >= addedAfter }
		}
		if let addedBefore = self.addedBefore {
			tracks = tracks.filter { $0.addedAtDate <= addedBefore }
		}
		if self.downloadedOnly {
			tracks = tracks.filter { DownloadManager.shared.isDownloaded(trackId: $0.id) }
		}

		let ascending = self.ascending
		func order<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool { ascending ? lhs < rhs : lhs > rhs }

		tracks.sort { lhs, rhs in
			switch self.sortBy {
				case .title: order(lhs.title.localizedLowercase, rhs.title.localizedLowercase)
				case .artist: order(lhs.artistName.localizedLowercase, rhs.artistName.localizedLowercase)
				case .album: order((lhs.album ?? "").localizedLowercase, (rhs.album ?? "").localizedLowercase)
				case .dateAdded: order(lhs.addedAt, rhs.addedAt)
				case .duration: order(lhs.duration, rhs.duration)
				case .releaseDate: order(lhs.releaseDate ?? 0, rhs.releaseDate ?? 0)
			}
		}

		if let limit = self.limit, limit > 0 {
			tracks = Array(tracks.prefix(limit))
		}
		return .result(value: tracks.map(SongEntity.init(row:)))
	}
}

struct FindLibraryAlbumsIntent: AppIntent {
	static let title: LocalizedStringResource = "Find Library Albums"
	static let description = IntentDescription("Finds albums in your Nafyn library, filtered and sorted.", categoryName: "Library")

	@Parameter(title: "Search")
	var searchText: String?

	@Parameter(title: "Artist")
	var artist: String?

	@Parameter(title: "Added After")
	var addedAfter: Date?

	@Parameter(title: "Added Before")
	var addedBefore: Date?

	@Parameter(title: "Minimum Tracks")
	var minimumTracks: Int?

	@Parameter(title: "Sort By", default: .dateAdded)
	var sortBy: AlbumSortOption

	@Parameter(title: "Ascending", default: false)
	var ascending: Bool

	@Parameter(title: "Limit", default: 25)
	var limit: Int?

	static var parameterSummary: some ParameterSummary {
		Summary("Find albums sorted by \(\.$sortBy)") {
			\.$searchText
			\.$artist
			\.$addedAfter
			\.$addedBefore
			\.$minimumTracks
			\.$ascending
			\.$limit
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<[AlbumEntity]> {
		var albums = try await LibraryCatalog.shared.albums()

		if let text = self.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
			albums = albums.filter { $0.title.localizedCaseInsensitiveContains(text) || $0.artistName.localizedCaseInsensitiveContains(text) }
		}
		if let artist = self.artist, !artist.isEmpty {
			albums = albums.filter { $0.artistName.localizedCaseInsensitiveContains(artist) }
		}
		if let addedAfter = self.addedAfter {
			albums = albums.filter { $0.addedAtDate >= addedAfter }
		}
		if let addedBefore = self.addedBefore {
			albums = albums.filter { $0.addedAtDate <= addedBefore }
		}
		if let minimumTracks = self.minimumTracks {
			albums = albums.filter { $0.trackCount >= minimumTracks }
		}

		let ascending = self.ascending
		func order<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool { ascending ? lhs < rhs : lhs > rhs }

		albums.sort { lhs, rhs in
			switch self.sortBy {
				case .title: order(lhs.title.localizedLowercase, rhs.title.localizedLowercase)
				case .artist: order(lhs.artistName.localizedLowercase, rhs.artistName.localizedLowercase)
				case .dateAdded: order(lhs.addedAt, rhs.addedAt)
				case .trackCount: order(lhs.trackCount, rhs.trackCount)
				case .duration: order(lhs.duration, rhs.duration)
				case .releaseDate: order(lhs.releaseDate ?? 0, rhs.releaseDate ?? 0)
			}
		}

		if let limit = self.limit, limit > 0 {
			albums = Array(albums.prefix(limit))
		}
		return .result(value: albums.map(AlbumEntity.init(row:)))
	}
}

struct GetPlaylistsIntent: AppIntent {
	static let title: LocalizedStringResource = "Get Playlists"
	static let description = IntentDescription("Gets your Nafyn playlists, including the ones shared with you.", categoryName: "Library")

	@Parameter(title: "Search")
	var searchText: String?

	@Parameter(title: "Created by Me Only", default: false)
	var createdByMeOnly: Bool

	@Parameter(title: "Sort By", default: .title)
	var sortBy: PlaylistSortOption

	@Parameter(title: "Ascending", default: true)
	var ascending: Bool

	static var parameterSummary: some ParameterSummary {
		Summary("Get playlists sorted by \(\.$sortBy)") {
			\.$searchText
			\.$createdByMeOnly
			\.$ascending
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<[PlaylistEntity]> {
		var playlists = try await LibraryCatalog.shared.playlists()

		if let text = self.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
			playlists = playlists.filter { $0.title.localizedCaseInsensitiveContains(text) }
		}
		if self.createdByMeOnly, let me = AppSession.shared.userId {
			playlists = playlists.filter { $0.ownerId == me }
		}

		let ascending = self.ascending
		playlists.sort { lhs, rhs in
			switch self.sortBy {
				case .title:
					ascending ? lhs.title.localizedLowercase < rhs.title.localizedLowercase : lhs.title.localizedLowercase > rhs.title.localizedLowercase
				case .dateUpdated:
					ascending ? lhs.updatedAt < rhs.updatedAt : lhs.updatedAt > rhs.updatedAt
			}
		}
		return .result(value: playlists.map(PlaylistEntity.init(row:)))
	}
}

// MARK: - Cover art

/// The cover as a high-resolution (1000 px) image file, ready for "Save to Photos", "Set Wallpaper", …
@MainActor
private func coverArtFile(path: String?, name: String) async throws -> IntentFile {
	_ = try await AppSession.shared.resolveServer()

	guard let url = path?.coverArtURL(size: 1000),
		  let data = await CoverArtLoader.shared.contents(of: url),
		  let image = UIImage(data: data),
		  let png = image.pngData()
	else { throw CoverArtError.unavailable }

	return IntentFile(data: png, filename: "\(name).png", type: .png)
}

enum CoverArtError: LocalizedError {
	case unavailable

	var errorDescription: String? {
		String(localized: "cover-art-unavailable")
	}
}

struct GetSongCoverArtIntent: AppIntent {
	static let title: LocalizedStringResource = "Get Song Cover Art"
	static let description = IntentDescription("Gets the cover art of a song in your library, in high resolution.", categoryName: "Library")

	@Parameter(title: "Song")
	var song: SongEntity

	static var parameterSummary: some ParameterSummary {
		Summary("Get cover art of \(\.$song)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
		.result(value: try await coverArtFile(path: self.song.coverArt, name: self.song.title))
	}
}

struct GetAlbumCoverArtIntent: AppIntent {
	static let title: LocalizedStringResource = "Get Album Cover Art"
	static let description = IntentDescription("Gets the cover art of an album in your library, in high resolution.", categoryName: "Library")

	@Parameter(title: "Album")
	var album: AlbumEntity

	static var parameterSummary: some ParameterSummary {
		Summary("Get cover art of \(\.$album)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
		.result(value: try await coverArtFile(path: self.album.coverArt, name: self.album.title))
	}
}

// MARK: - Playing

struct PlaySongIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Play Song"
	static let description = IntentDescription("Plays a song from your Nafyn library.", categoryName: "Playback")

	@Parameter(title: "Song")
	var song: SongEntity

	@Parameter(title: "Continue with Album", default: false)
	var continueWithAlbum: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("Play \(\.$song)") {
			\.$continueWithAlbum
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		var queue = try await AudioPlayback.queue(song: self.song.id)

		// the rest of the album after this track
		if self.continueWithAlbum, let track = queue.tracks.first {
			let album = try await LibraryCatalog.shared.tracks(ofAlbum: track.albumId)
			if let index = album.firstIndex(where: { $0.id == track.id }) {
				queue.tracks = Array(album[index...])
			}
		}

		try AudioPlayback.start(queue, shuffle: false, repeatMode: self.repeatMode)
		return .result()
	}
}

struct PlayAlbumIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Play Album"
	static let description = IntentDescription("Plays an album from your Nafyn library.", categoryName: "Playback")

	@Parameter(title: "Album")
	var album: AlbumEntity

	@Parameter(title: "Shuffle", default: false)
	var shuffle: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("Play \(\.$album)") {
			\.$shuffle
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		let queue = try await AudioPlayback.queue(album: self.album.id)
		try AudioPlayback.start(queue, shuffle: self.shuffle, repeatMode: self.repeatMode)
		return .result()
	}
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Play Playlist"
	static let description = IntentDescription("Plays a Nafyn playlist.", categoryName: "Playback")

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	@Parameter(title: "Shuffle", default: false)
	var shuffle: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("Play \(\.$playlist)") {
			\.$shuffle
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		let queue = try await AudioPlayback.queue(playlist: self.playlist.id)
		try AudioPlayback.start(queue, shuffle: self.shuffle, repeatMode: self.repeatMode)
		return .result()
	}
}

struct ShuffleLibraryIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Shuffle My Library"
	static let description = IntentDescription("Plays your whole Nafyn library in random order.", categoryName: "Playback")

	@MainActor
	func perform() async throws -> some IntentResult {
		let tracks = try await LibraryCatalog.shared.tracks()
		try AudioPlayback.start(AudioPlayback.Queue(tracks: tracks, context: nil), shuffle: true, repeatQueue: true)
		return .result()
	}
}

// MARK: - Transport

struct PauseNafynIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Pause Nafyn"

	@MainActor
	func perform() async throws -> some IntentResult {
		if PlaybackSource.isPlaying { PlaybackSource.togglePlay() }
		return .result()
	}
}

struct ResumeNafynIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Resume Nafyn"

	@MainActor
	func perform() async throws -> some IntentResult {
		if !PlaybackSource.isPlaying, PlaybackSource.hasTrack { PlaybackSource.togglePlay() }
		return .result()
	}
}

struct NextTrackIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Next Track"

	@MainActor
	func perform() async throws -> some IntentResult {
		PlaybackSource.next()
		return .result()
	}
}

struct PreviousTrackIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "Previous Track"

	@MainActor
	func perform() async throws -> some IntentResult {
		PlaybackSource.prev()
		return .result()
	}
}

// MARK: - Playlists

struct AddSongToPlaylistIntent: AppIntent {
	static let title: LocalizedStringResource = "Add Song to Playlist"
	static let description = IntentDescription("Adds a song from your library to one of your playlists.", categoryName: "Playlists")

	@Parameter(title: "Song")
	var song: SongEntity

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	static var parameterSummary: some ParameterSummary {
		Summary("Add \(\.$song) to \(\.$playlist)")
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		let queue = try await AudioPlayback.queue(song: self.song.id)
		try await AudioPlayback.add(queue.tracks, toPlaylist: self.playlist.id)
		return .result()
	}
}

struct RemoveSongFromPlaylistIntent: AppIntent {
	static let title: LocalizedStringResource = "Remove Song from Playlist"
	static let description = IntentDescription("Removes a song from one of your playlists. The song stays in your library.", categoryName: "Playlists")

	@Parameter(title: "Song")
	var song: SongEntity

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	static var parameterSummary: some ParameterSummary {
		Summary("Remove \(\.$song) from \(\.$playlist)")
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		let server = try await AppSession.shared.resolveServer()
		let songId = self.song.id

		// a playlist entry is the song's place in the list: find every one of this song
		var entryIds: [String] = []
		var page = 1
		while true {
			let response = try await server.fetchPlaylistTracks(pid: self.playlist.id, page: page, limit: 100)
			entryIds += response.items.filter { $0.media.id == songId }.map(\.entryId)
			guard response.hasMore else { break }
			page += 1
		}
		guard !entryIds.isEmpty else { throw AudioPlaybackError.notInPlaylist }

		for entryId in entryIds {
			_ = try await server.sendRaw(Playlist.removeTrack(pid: self.playlist.id, eid: entryId))
		}
		await LibraryCatalog.shared.invalidate()
		return .result()
	}
}

// MARK: - Opening (Spotlight results)

struct OpenSongIntent: OpenIntent {
	static let title: LocalizedStringResource = "Open Song"

	@Parameter(title: "Song")
	var target: SongEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .libraryTrack(id: self.target.id))
		return .result()
	}
}

struct OpenAlbumIntent: OpenIntent {
	static let title: LocalizedStringResource = "Open Album"

	@Parameter(title: "Album")
	var target: AlbumEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .libraryAlbum(id: self.target.id))
		return .result()
	}
}

struct OpenPlaylistIntent: OpenIntent {
	static let title: LocalizedStringResource = "Open Playlist"

	@Parameter(title: "Playlist")
	var target: PlaylistEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .playlist(id: self.target.id))
		return .result()
	}
}
