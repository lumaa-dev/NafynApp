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

	var title: String
	var artistName: String
	var artists: [ArtistEntity]
	var universalProductCode: String?

	@Property(title: "Track Count")
	var trackCount: Int

	@Property(title: "Duration")
	var duration: Measurement<UnitDuration>

	@Property(title: "Date Added")
	var dateAdded: Date

	@Property(title: "Release Date")
	var releaseDate: Date?

	var coverArt: String?

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(self.title)", subtitle: "\(self.artistName)")
	}

	var attributeSet: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(contentType: .audio)
		attributes.title = self.title
		attributes.album = self.title
		attributes.artist = self.artistName
		attributes.contentDescription = self.artistName
		attributes.keywords = [self.title, self.artistName]
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
		self.coverArt = coverArt
	}

	struct AlbumEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
		typealias Entity = AlbumEntity
		func entities(for identifiers: [AlbumEntity.ID]) async throws -> [AlbumEntity] {
			let wanted = Set(identifiers)
			return try await LibraryCatalog.shared.albums().filter { wanted.contains($0.id) }.map(AlbumEntity.init(row:))
		}

		func entities(matching string: String) async throws -> [AlbumEntity] {
			try await LibraryCatalog.shared.albums()
				.filter { $0.title.localizedCaseInsensitiveContains(string) || $0.artistName.localizedCaseInsensitiveContains(string) }
				.map(AlbumEntity.init(row:))
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
