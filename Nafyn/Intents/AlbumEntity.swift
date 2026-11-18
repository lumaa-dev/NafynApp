// Made by Lumaa

import AppIntents
import UniformTypeIdentifiers
import CoreSpotlight
import Foundation
import Safyn

// MARK: - Album

@AppEntity(schema: .audio.album)
struct AlbumEntity: IndexedEntity {
	typealias DefaultQuery = AlbumEntityQuery
	static let defaultQuery: AlbumEntityQuery = AlbumEntityQuery()

	/// The library album ID.
	let id: String

	@Property(title: "Title", indexingKey: \.title)
	var title: String

	@Property(title: "Artist", indexingKey: \.artist)
	var artistName: String

	@Property(title: "Artists")
	var artists: [ArtistEntity]

	@Property(title: "UPC")
	var universalProductCode: String?

	@Property(title: "intent-property-track-count")
	var trackCount: Int

	@Property(title: "Duration")
	var duration: Measurement<UnitDuration>

	@Property(title: "intent-property-date-added")
	var dateAdded: Date

	@Property(title: "intent-property-release-date")
	var releaseDate: Date?

	@Property(title: "intent-property-mbid")
	var musicBrainzId: String

	@Property(title: "intent-property-artist-mbid")
	var artistMusicBrainzId: String?

	@Property(title: "intent-property-cover-art-path")
	var coverArt: String?

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(self.title)",
			subtitle: "\(self.artistName)",
			image: IntentArtwork.data(for: self.coverArt).map { DisplayRepresentation.Image(data: $0) }
		)
	}

	var attributeSet: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(contentType: .audio)
		attributes.title = self.title
		attributes.album = self.title
		attributes.artist = self.artistName
		attributes.contentDescription = self.artistName
		attributes.keywords = [self.title, self.artistName]
		attributes.thumbnailData = IntentArtwork.data(for: self.coverArt)
		return attributes
	}

	init(row: AlbumRow) {
		self.id = row.id
		self.title = row.title
		self.artistName = row.artistName
		self.artists = [ArtistEntity(name: row.artistName)]
		self.universalProductCode = nil
		self.trackCount = row.trackCount
		self.duration = Measurement(value: row.duration, unit: .seconds)
		self.dateAdded = row.addedAtDate
		self.releaseDate = row.releaseDateValue
		self.musicBrainzId = row.mbId
		self.artistMusicBrainzId = row.artistMbid
		self.coverArt = row.coverArt
	}

	/// An album known only through one of its tracks (a song's `album`).
	init(albumId: String, title: String, artistName: String, coverArt: String?) {
		self.id = albumId
		self.title = title
		self.artistName = artistName
		self.artists = [ArtistEntity(name: artistName)]
		self.universalProductCode = nil
		self.trackCount = 0
		self.duration = Measurement(value: 0, unit: .seconds)
		self.dateAdded = .distantPast
		self.releaseDate = nil
		self.musicBrainzId = albumId
		self.artistMusicBrainzId = nil
		self.coverArt = coverArt
	}

	struct AlbumEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
		typealias Entity = AlbumEntity
		func entities(for identifiers: [AlbumEntity.ID]) async throws -> [AlbumEntity] {
			let wanted = Set(identifiers)
			return try await LibraryCatalog.shared.albums().filter { wanted.contains($0.id) }.map(AlbumEntity.init(row:))
		}

		func entities(matching string: String) async throws -> [AlbumEntity] {
			LibrarySearch.albums(try await LibraryCatalog.shared.albums(), matching: string)
				.prefix(50)
				.map { AlbumEntity(row: $0.row) }
		}

		func suggestedEntities() async throws -> [AlbumEntity] {
			try await LibraryCatalog.shared.albums()
				.sorted { $0.addedAt > $1.addedAt }
				.prefix(25)
				.map(AlbumEntity.init(row:))
		}

		func reindexEntities(for identifiers: [AlbumEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
			let albums = try await self.entities(for: identifiers)
			try await CSSearchableIndex(name: SpotlightIndexer.indexName).indexAppEntities(albums)
		}

		func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
			await SpotlightIndexer.shared.syncNow()
		}
	}
}
