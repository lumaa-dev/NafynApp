// Made by Lumaa

import AppIntents
import Foundation
import Safyn

/// Any one thing of the user's library that can be played: a song, an album, an artist or a playlist. It is
/// what lets one Siri phrase ("Put The Vows on Nafyn") take any name, whatever kind it is, the way
/// Spotify's "Play …" does, instead of needing "the album …" or "the song …" in the sentence.
struct LibraryItemEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent-type-library-item")
	static let defaultQuery = LibraryItemQuery()

	enum Kind: String {
		case song
		case album
		case artist
		case playlist
	}

	/// `kind:id`, the ID being the library's own (an artist's is the name).
	let id: String

	@Property(title: "Name")
	var title: String

	@Property(title: "Details")
	var details: String

	let coverArt: String?

	var kind: Kind {
		Kind(rawValue: String(self.id.prefix { $0 != ":" })) ?? .song
	}

	var itemId: String {
		String(self.id.drop { $0 != ":" }.dropFirst())
	}

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(self.title)",
			subtitle: "\(self.details)",
			image: IntentArtwork.data(for: self.coverArt).map { DisplayRepresentation.Image(data: $0) }
				?? .init(systemName: self.symbol)
		)
	}

	private var symbol: String {
		switch self.kind {
			case .song: "music.note"
			case .album: "square.stack"
			case .artist: "music.mic"
			case .playlist: "music.note.list"
		}
	}

	init(kind: Kind, itemId: String, title: String, details: String, coverArt: String?) {
		self.id = "\(kind.rawValue):\(itemId)"
		self.coverArt = coverArt
		self.title = title
		self.details = details
	}

	init(song row: MediaRow) {
		self.init(kind: .song, itemId: row.id, title: row.title, details: row.artistName, coverArt: row.coverArt)
	}

	init(album row: AlbumRow) {
		self.init(kind: .album, itemId: row.id, title: row.title, details: row.artistName, coverArt: row.coverArt)
	}

	init(artist name: String, coverArt: String? = nil) {
		self.init(kind: .artist, itemId: name, title: name, details: String(localized: "Artist"), coverArt: coverArt)
	}

	init(playlist row: PlaylistRow) {
		self.init(kind: .playlist, itemId: row.id, title: row.title, details: String(localized: "Playlist"), coverArt: nil)
	}

	/// The queue this item plays.
	func queue() async throws -> AudioPlayback.Queue {
		switch self.kind {
			case .song: try await AudioPlayback.queue(song: self.itemId)
			case .album: try await AudioPlayback.queue(album: self.itemId)
			case .artist: try await AudioPlayback.queue(artist: self.itemId)
			case .playlist: try await AudioPlayback.queue(playlist: self.itemId)
		}
	}

	struct LibraryItemQuery: EntityStringQuery {
		func entities(for identifiers: [LibraryItemEntity.ID]) async throws -> [LibraryItemEntity] {
			let wanted = Set(identifiers)
			return try await Self.everything().filter { wanted.contains($0.id) }
		}

		func entities(matching string: String) async throws -> [LibraryItemEntity] {
			async let tracks = LibraryCatalog.shared.tracks()
			async let albums = LibraryCatalog.shared.albums()
			async let playlists = LibraryCatalog.shared.playlists()

			let allTracks = try await tracks
			var scored: [(score: Int, kind: Int, item: LibraryItemEntity)] = []

			for match in LibrarySearch.albums(try await albums, matching: string).prefix(10) {
				scored.append((match.score, 1, LibraryItemEntity(album: match.row)))
			}
			for match in LibrarySearch.artists(LibrarySearch.artistNames(in: allTracks), matching: string).prefix(10) {
				scored.append((match.score, 2, LibraryItemEntity(artist: match.row)))
			}
			for match in LibrarySearch.tracks(allTracks, matching: string).prefix(10) {
				scored.append((match.score, 0, LibraryItemEntity(song: match.row)))
			}
			for match in LibrarySearch.playlists((try? await playlists) ?? [], matching: string).prefix(5) {
				scored.append((match.score, 3, LibraryItemEntity(playlist: match.row)))
			}

			return scored
				.enumerated()
				.sorted { ($0.element.score, $0.element.kind, $0.offset) < ($1.element.score, $1.element.kind, $1.offset) }
				.prefix(10)
				.map(\.element.item)
		}

		/// What Siri learns to recognize in a spoken request: the playlists and the newest music, so a
		/// phrase works for them straight away.
		func suggestedEntities() async throws -> [LibraryItemEntity] {
			async let tracks = LibraryCatalog.shared.tracks()
			async let albums = LibraryCatalog.shared.albums()
			async let playlists = LibraryCatalog.shared.playlists()

			let allTracks = try await tracks
			var items: [LibraryItemEntity] = ((try? await playlists) ?? []).map(LibraryItemEntity.init(playlist:))
			items += LibrarySearch.artistNames(in: allTracks).prefix(150).map { LibraryItemEntity(artist: $0) }
			items += try await albums.sorted { $0.addedAt > $1.addedAt }.prefix(300).map(LibraryItemEntity.init(album:))
			items += allTracks.sorted { $0.addedAt > $1.addedAt }.prefix(300).map(LibraryItemEntity.init(song:))
			return items
		}

		private static func everything() async throws -> [LibraryItemEntity] {
			async let tracks = LibraryCatalog.shared.tracks()
			async let albums = LibraryCatalog.shared.albums()
			async let playlists = LibraryCatalog.shared.playlists()

			let allTracks = try await tracks
			var items = try await albums.map(LibraryItemEntity.init(album:))
			items += LibrarySearch.artistNames(in: allTracks).map { LibraryItemEntity(artist: $0) }
			items += allTracks.map(LibraryItemEntity.init(song:))
			items += ((try? await playlists) ?? []).map(LibraryItemEntity.init(playlist:))
			return items
		}
	}
}
