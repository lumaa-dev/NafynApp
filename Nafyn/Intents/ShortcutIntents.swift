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

/// One search for everything the library holds. The kind picks what comes back (and which filters apply);
/// the results are Nafyn entities, so a shortcut reads their title, duration, file size, MusicBrainz ID, …
struct FindLibraryItemsIntent: AppIntent {
	static let title: LocalizedStringResource = "intent-find-library-items"
	static let description = IntentDescription("intent-find-library-items-description", categoryName: "Library")

	@Parameter(title: "intent-property-content-type", default: .tracks)
	var kind: LibraryContentKind

	@Parameter(title: "Search")
	var searchText: String?

	@Parameter(title: "Artist")
	var artist: String?

	@Parameter(title: "Album")
	var album: String?

	@Parameter(title: "intent-param-added-after")
	var addedAfter: Date?

	@Parameter(title: "intent-param-added-before")
	var addedBefore: Date?

	@Parameter(title: "intent-param-minimum-tracks")
	var minimumTracks: Int?

	@Parameter(title: "intent-param-downloaded-only", default: false)
	var downloadedOnly: Bool

	@Parameter(title: "intent-param-created-by-me-only", default: false)
	var createdByMeOnly: Bool

	@Parameter(title: "intent-param-sort-by", default: .dateAdded)
	var sortBy: LibrarySortOption

	@Parameter(title: "Ascending", default: false)
	var ascending: Bool

	@Parameter(title: "Limit", default: 25)
	var limit: Int?

	static var parameterSummary: some ParameterSummary {
		Switch(\.$kind) {
			Case(.tracks) {
				Summary("summary-find-library-items \(\.$kind) \(\.$sortBy)") {
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
			Case(.albums) {
				Summary("summary-find-library-items \(\.$kind) \(\.$sortBy)") {
					\.$searchText
					\.$artist
					\.$addedAfter
					\.$addedBefore
					\.$minimumTracks
					\.$ascending
					\.$limit
				}
			}
			Case(.playlists) {
				Summary("summary-find-library-items \(\.$kind) \(\.$sortBy)") {
					\.$searchText
					\.$createdByMeOnly
					\.$ascending
					\.$limit
				}
			}
			DefaultCase {
				Summary("summary-find-library-items \(\.$kind) \(\.$sortBy)") {
					\.$searchText
					\.$ascending
					\.$limit
				}
			}
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<[AudioItem]> {
		let items: [AudioItem]
		switch self.kind {
			case .tracks: items = try await self.tracks()
			case .albums: items = try await self.albums()
			case .artists: items = try await self.artists()
			case .playlists: items = try await self.playlists()
		}

		if let limit = self.limit, limit > 0 {
			return .result(value: Array(items.prefix(limit)))
		}
		return .result(value: items)
	}

	// MARK: Kinds

	@MainActor
	private func tracks() async throws -> [AudioItem] {
		var tracks = try await LibraryCatalog.shared.tracks()

		if let text = self.searchText, !text.trimmingCharacters(in: .whitespaces).isEmpty {
			tracks = LibrarySearch.tracks(tracks, matching: text).map(\.row)
		}
		if let artist = self.artist, !artist.isEmpty {
			tracks = tracks.filter { LibrarySearch.score(artist, in: [$0.artistName]) != nil }
		}
		if let album = self.album, !album.isEmpty {
			tracks = tracks.filter { LibrarySearch.score(album, in: [$0.album]) != nil }
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

		let sorted = self.sort(tracks) { track in
			switch self.sortBy {
				case .artist: .text(track.artistName)
				case .album: .text(track.album ?? "")
				case .dateAdded: .number(Double(track.addedAt))
				case .duration: .number(track.duration)
				case .releaseDate: .number(Double(track.releaseDate ?? 0))
				case .trackCount: .number(track.trackNumber ?? 0)
				case .fileSize: .number(Double(track.fileSize ?? 0))
				case .title: .text(track.title)
			}
		}
		return sorted.map { .song(SongEntity(row: $0)) }
	}

	@MainActor
	private func albums() async throws -> [AudioItem] {
		var albums = try await LibraryCatalog.shared.albums()

		if let text = self.searchText, !text.trimmingCharacters(in: .whitespaces).isEmpty {
			albums = LibrarySearch.albums(albums, matching: text).map(\.row)
		}
		if let artist = self.artist, !artist.isEmpty {
			albums = albums.filter { LibrarySearch.score(artist, in: [$0.artistName]) != nil }
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

		let sorted = self.sort(albums) { album in
			switch self.sortBy {
				case .artist: .text(album.artistName)
				case .dateAdded: .number(Double(album.addedAt))
				case .duration: .number(album.duration)
				case .releaseDate: .number(Double(album.releaseDate ?? 0))
				case .trackCount: .number(Double(album.trackCount))
				case .title, .album, .fileSize: .text(album.title)
			}
		}
		return sorted.map { .album(AlbumEntity(row: $0)) }
	}

	@MainActor
	private func artists() async throws -> [AudioItem] {
		var names = LibrarySearch.artistNames(in: try await LibraryCatalog.shared.tracks())

		if let text = self.searchText, !text.trimmingCharacters(in: .whitespaces).isEmpty {
			names = LibrarySearch.artists(names, matching: text).map(\.row)
		}
		return self.sort(names) { .text($0) }.map { .artist(ArtistEntity(name: $0)) }
	}

	@MainActor
	private func playlists() async throws -> [AudioItem] {
		var playlists = try await LibraryCatalog.shared.playlists()

		if let text = self.searchText, !text.trimmingCharacters(in: .whitespaces).isEmpty {
			playlists = LibrarySearch.playlists(playlists, matching: text).map(\.row)
		}
		if self.createdByMeOnly, let me = AppSession.shared.userId {
			playlists = playlists.filter { $0.ownerId == me }
		}

		let sorted = self.sort(playlists) { playlist in
			switch self.sortBy {
				case .dateAdded, .releaseDate: .number(Double(playlist.updatedAt))
				default: .text(playlist.title)
			}
		}
		return sorted.map { .playlist(PlaylistEntity(row: $0)) }
	}

	// MARK: Sorting

	private struct SortValue: Comparable {
		var number = 0.0
		var text = ""

		static func text(_ text: String) -> SortValue { SortValue(text: LibrarySearch.normalize(text)) }
		static func number(_ number: Double) -> SortValue { SortValue(number: number) }

		static func < (lhs: SortValue, rhs: SortValue) -> Bool {
			(lhs.number, lhs.text) < (rhs.number, rhs.text)
		}
	}

	private func sort<Row>(_ rows: [Row], by value: (Row) -> SortValue) -> [Row] {
		let keyed = rows.map { (value($0), $0) }
		let ordered = keyed.sorted { self.ascending ? $0.0 < $1.0 : $1.0 < $0.0 }
		return ordered.map(\.1)
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
	static let title: LocalizedStringResource = "intent-get-song-cover"
	static let description = IntentDescription("intent-get-song-cover-description", categoryName: "Library")

	@Parameter(title: "Song")
	var song: SongEntity

	static var parameterSummary: some ParameterSummary {
		Summary("summary-get-song-cover \(\.$song)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
		.result(value: try await coverArtFile(path: self.song.coverArt, name: self.song.title))
	}
}

struct GetAlbumCoverArtIntent: AppIntent {
	static let title: LocalizedStringResource = "intent-get-album-cover"
	static let description = IntentDescription("intent-get-album-cover-description", categoryName: "Library")

	@Parameter(title: "Album")
	var album: AlbumEntity

	static var parameterSummary: some ParameterSummary {
		Summary("summary-get-album-cover \(\.$album)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
		.result(value: try await coverArtFile(path: self.album.coverArt, name: self.album.title))
	}
}

// MARK: - Playing

struct PlaySongIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-play-song"
	static let description = IntentDescription("intent-play-song-description", categoryName: "Playback")

	@Parameter(title: "Song")
	var song: SongEntity

	@Parameter(title: "intent-param-continue-with-album", default: false)
	var continueWithAlbum: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("summary-play-song \(\.$song)") {
			\.$continueWithAlbum
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		var queue = try await AudioPlayback.queue(song: self.song.id)

		// the rest of the album after this track
		if self.continueWithAlbum, let track = queue.tracks.first {
			let album = try await LibraryCatalog.shared.tracks(ofAlbum: track.albumId)
			if let index = album.firstIndex(where: { $0.id == track.id }) {
				queue.tracks = Array(album[index...])
			}
		}

		let outcome = try AudioPlayback.start(queue, shuffle: false, repeatMode: self.repeatMode)
		return .result(dialog: AudioPlayback.dialog(outcome, title: queue.title))
	}
}

struct PlayAlbumIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-play-album"
	static let description = IntentDescription("intent-play-album-description", categoryName: "Playback")

	@Parameter(title: "Album")
	var album: AlbumEntity

	@Parameter(title: "Shuffle", default: false)
	var shuffle: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("summary-play-album \(\.$album)") {
			\.$shuffle
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let queue = try await AudioPlayback.queue(album: self.album.id)
		let outcome = try AudioPlayback.start(queue, shuffle: self.shuffle, repeatMode: self.repeatMode)
		return .result(dialog: AudioPlayback.dialog(outcome, title: queue.title))
	}
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-play-playlist"
	static let description = IntentDescription("intent-play-playlist-description", categoryName: "Playback")

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	@Parameter(title: "Shuffle", default: false)
	var shuffle: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("summary-play-playlist \(\.$playlist)") {
			\.$shuffle
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let queue = try await AudioPlayback.queue(playlist: self.playlist.id)
		let outcome = try AudioPlayback.start(queue, shuffle: self.shuffle, repeatMode: self.repeatMode)
		return .result(dialog: AudioPlayback.dialog(outcome, title: queue.title))
	}
}

/// "Play …" for anything by name: Siri's catch-all, whether the name is a song, an album, an artist or a playlist.
struct PlayLibraryItemIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-play-anything"
	static let description = IntentDescription("intent-play-anything-description", categoryName: "Playback")

	@Parameter(title: "Item")
	var item: LibraryItemEntity

	@Parameter(title: "Shuffle", default: false)
	var shuffle: Bool

	@Parameter(title: "Repeat", default: .off)
	var repeatMode: RepeatOption

	static var parameterSummary: some ParameterSummary {
		Summary("summary-play-item \(\.$item)") {
			\.$shuffle
			\.$repeatMode
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let queue = try await self.item.queue()
		let outcome = try AudioPlayback.start(queue, shuffle: self.shuffle, repeatMode: self.repeatMode)
		return .result(dialog: AudioPlayback.dialog(outcome, title: queue.title))
	}
}

struct ShuffleLibraryIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-shuffle-library"
	static let description = IntentDescription("intent-shuffle-library-description", categoryName: "Playback")

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let tracks = try await LibraryCatalog.shared.tracks()
		try AudioPlayback.start(AudioPlayback.Queue(tracks: tracks, context: nil), shuffle: true, repeatQueue: true)
		return .result(dialog: "dialog-shuffling-library")
	}
}

// MARK: - Transport

/// Play, pause, skip: one action instead of one per button.
struct ControlPlaybackIntent: AudioPlaybackIntent {
	static let title: LocalizedStringResource = "intent-control-playback"
	static let description = IntentDescription("intent-control-playback-description", categoryName: "Playback")

	@Parameter(title: "Action", default: .togglePlayPause)
	var action: PlaybackAction

	static var parameterSummary: some ParameterSummary {
		Summary("summary-control-playback \(\.$action)")
	}

	init() {}

	init(action: PlaybackAction) {
		self.action = action
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		guard PlaybackSource.hasTrack else {
			return .result(dialog: "dialog-nothing-playing")
		}

		switch self.action {
			case .play:
				if !PlaybackSource.isPlaying { PlaybackSource.togglePlay() }
				return .result(dialog: "dialog-resuming")
			case .pause:
				if PlaybackSource.isPlaying { PlaybackSource.togglePlay() }
				return .result(dialog: "Paused.")
			case .togglePlayPause:
				let wasPlaying = PlaybackSource.isPlaying
				PlaybackSource.togglePlay()
				return wasPlaying ? .result(dialog: "Paused.") : .result(dialog: "dialog-resuming")
			case .next:
				PlaybackSource.next()
				return .result(dialog: "dialog-next-track")
			case .previous:
				PlaybackSource.prev()
				return .result(dialog: "dialog-previous-track")
		}
	}
}

// MARK: - Playlists

/// Creates a playlist, with songs and albums already in it if the shortcut has some.
struct CreatePlaylistIntent: AppIntent {
	static let title: LocalizedStringResource = "intent-create-playlist"
	static let description = IntentDescription("intent-create-playlist-description", categoryName: "Playlists")

	@Parameter(title: "Name")
	var name: String

	@Parameter(title: "Description")
	var summary: String?

	@Parameter(title: "Visibility", default: .private)
	var visibility: PlaylistVisibility

	@Parameter(title: "Songs", default: [])
	var songs: [SongEntity]

	@Parameter(title: "Albums", default: [])
	var albums: [AlbumEntity]

	static var parameterSummary: some ParameterSummary {
		Summary("summary-create-playlist \(\.$name)") {
			\.$summary
			\.$visibility
			\.$songs
			\.$albums
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<PlaylistEntity> & ProvidesDialog {
		let title = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty else { throw AudioPlaybackError.emptyName }

		let server = try await AppSession.shared.resolveServer()
		let description = self.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
		let row: PlaylistRow = try await server.send(Playlist.create(
			title: title,
			description: (description?.isEmpty ?? true) ? nil : description,
			privacy: self.visibility == .public ? .public : .private
		))

		let tracks = try await AudioPlayback.tracks(songs: self.songs.map(\.id), albums: self.albums.map(\.id))
		if !tracks.isEmpty {
			try await AudioPlayback.add(tracks, toPlaylist: row.id)
		}
		await LibraryCatalog.shared.invalidatePlaylists()

		return .result(value: PlaylistEntity(row: row), dialog: "dialog-created-playlist \(title)")
	}
}

/// Adds any number of songs and albums to a playlist in one go.
struct AddToPlaylistIntent: AppIntent {
	static let title: LocalizedStringResource = "intent-add-to-playlist"
	static let description = IntentDescription("intent-add-to-playlist-description", categoryName: "Playlists")

	@Parameter(title: "Songs", default: [])
	var songs: [SongEntity]

	@Parameter(title: "Albums", default: [])
	var albums: [AlbumEntity]

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	static var parameterSummary: some ParameterSummary {
		Summary("summary-add-to-playlist \(\.$songs) \(\.$albums) \(\.$playlist)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let tracks = try await AudioPlayback.tracks(songs: self.songs.map(\.id), albums: self.albums.map(\.id))
		try await AudioPlayback.add(tracks, toPlaylist: self.playlist.id)

		let name = await AudioPlayback.playlistTitle(self.playlist.id)
		return .result(dialog: "dialog-added-to-playlist \(name)")
	}
}

/// Takes songs out of a playlist; they stay in the library.
struct RemoveFromPlaylistIntent: AppIntent {
	static let title: LocalizedStringResource = "remove-from-playlist"
	static let description = IntentDescription("intent-remove-from-playlist-description", categoryName: "Playlists")

	@Parameter(title: "Songs")
	var songs: [SongEntity]

	@Parameter(title: "Playlist")
	var playlist: PlaylistEntity

	static var parameterSummary: some ParameterSummary {
		Summary("summary-remove-from-playlist \(\.$songs) \(\.$playlist)")
	}

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let server = try await AppSession.shared.resolveServer()
		let songIds = Set(self.songs.map(\.id))

		// a playlist entry is the song's place in the list: find every one of these songs
		var entryIds: [String] = []
		var page = 1
		while true {
			let response = try await server.fetchPlaylistTracks(pid: self.playlist.id, page: page, limit: 100)
			entryIds += response.items.filter { songIds.contains($0.media.id) }.map(\.entryId)
			guard response.hasMore else { break }
			page += 1
		}
		guard !entryIds.isEmpty else { throw AudioPlaybackError.notInPlaylist }

		for entryId in entryIds {
			_ = try await server.sendRaw(Playlist.removeTrack(pid: self.playlist.id, eid: entryId))
		}
		await LibraryCatalog.shared.invalidatePlaylists()

		let name = await AudioPlayback.playlistTitle(self.playlist.id)
		return .result(dialog: "dialog-removed-from-playlist \(name)")
	}
}

// MARK: - Opening (Spotlight results)

struct OpenSongIntent: OpenIntent {
	static let title: LocalizedStringResource = "intent-open-song"

	@Parameter(title: "Song")
	var target: SongEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .libraryTrack(id: self.target.id))
		return .result()
	}
}

struct OpenAlbumIntent: OpenIntent {
	static let title: LocalizedStringResource = "intent-open-album"

	@Parameter(title: "Album")
	var target: AlbumEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .libraryAlbum(id: self.target.id))
		return .result()
	}
}

struct OpenPlaylistIntent: OpenIntent {
	static let title: LocalizedStringResource = "intent-open-playlist"

	@Parameter(title: "Playlist")
	var target: PlaylistEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		Navigator.shared.send(to: .playlist(id: self.target.id))
		return .result()
	}
}
