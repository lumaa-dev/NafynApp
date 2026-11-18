// Made by Lumaa

import AppIntents
import UniformTypeIdentifiers
import CoreSpotlight
import Foundation
import Safyn

// MARK: - Song

@AppEntity(schema: .audio.song)
struct SongEntity: IndexedEntity {
	typealias DefaultQuery = SongEntityQuery
	static let defaultQuery: SongEntityQuery = SongEntityQuery()

	/// Nafyn's media ID.
	let id: String

	@Property(title: "Title", indexingKey: \.title)
	var title: String

	@Property(title: "Artist", indexingKey: \.artist)
	var artistName: String

	@Property(title: "Composer", indexingKey: \.composer)
	var composerName: String?

	@Property(title: "intent-property-album-title", indexingKey: \.album)
	var albumTitle: String?

	@Property(title: "Artists")
	var artists: [ArtistEntity]

	@Property(title: "Album")
	var album: AlbumEntity?

	@Property(title: "Composers")
	var composers: [ArtistEntity]

	@Property(title: "ISRC", indexingKey: \.identifier)
	var internationalStandardRecordingCode: String?

	@Property(title: "Duration")
	var duration: Measurement<UnitDuration>

	@Property(title: "intent-property-date-added")
	var dateAdded: Date

	@Property(title: "intent-property-track-number")
	var trackNumber: Int?

	@Property(title: "intent-property-disc-number")
	var discNumber: Int?

	@Property(title: "intent-property-release-date")
	var releaseDate: Date?

	@Property(title: "intent-property-file-size")
	var fileSize: Measurement<UnitInformationStorage>?

	@Property(title: "record-label")
	var label: String?

	@Property(title: "album-type")
	var albumType: String?

	@Property(title: "intent-property-mbid")
	var musicBrainzId: String

	@Property(title: "intent-property-artist-mbid")
	var artistMusicBrainzId: String?

	@Property(title: "intent-property-album-mbid")
	var albumMusicBrainzId: String

	@Property(title: "intent-property-cover-art-path")
	var coverArt: String?

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(self.title)",
			subtitle: "\(self.artistName)",
			image: IntentArtwork.data(for: self.coverArt).map { DisplayRepresentation.Image(data: $0) }
		)
	}

	/// What Spotlight searches besides the properties: artist and album names, so "Fontaines" finds the track.
	var attributeSet: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(contentType: .audio)
		attributes.title = self.title
		attributes.artist = self.artistName
		attributes.album = self.albumTitle
		attributes.audioTrackNumber = self.trackNumber.map { NSNumber(value: $0) }
		attributes.duration = NSNumber(value: self.duration.converted(to: .seconds).value)
		attributes.contentDescription = [self.artistName, self.albumTitle].compactMap { $0 }.joined(separator: " • ")
		attributes.keywords = [self.title, self.artistName, self.albumTitle].compactMap { $0 }
		attributes.thumbnailData = IntentArtwork.data(for: self.coverArt)
		return attributes
	}

	init(row: MediaRow) {
		self.id = row.id
		self.title = row.title
		self.artistName = row.artistName
		self.composerName = nil
		self.albumTitle = row.album
		self.artists = [ArtistEntity(name: row.artistName)]
		self.album = row.album.map { AlbumEntity(albumId: row.albumId, title: $0, artistName: row.artistName, coverArt: row.coverArt) }
		self.composers = []
		self.internationalStandardRecordingCode = nil
		self.duration = Measurement(value: row.duration, unit: .seconds)
		self.dateAdded = row.addedAtDate
		self.trackNumber = row.trackNumber.map { Int($0) }
		self.releaseDate = row.releaseDateValue
		self.discNumber = row.discNumber.map { Int($0) }
		self.fileSize = row.fileSize.map { Measurement(value: Double($0), unit: .bytes) }
		self.label = row.label
		self.albumType = row.albumType?.rawValue
		self.musicBrainzId = row.musicbrainzId
		self.artistMusicBrainzId = row.artistMbid
		self.albumMusicBrainzId = row.albumId
		self.coverArt = row.coverArt
	}

	struct SongEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
		typealias Entity = SongEntity
		func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
			let wanted = Set(identifiers)
			return try await LibraryCatalog.shared.tracks().filter { wanted.contains($0.id) }.map(SongEntity.init(row:))
		}

		func entities(matching string: String) async throws -> [SongEntity] {
			LibrarySearch.tracks(try await LibraryCatalog.shared.tracks(), matching: string)
				.prefix(50)
				.map { SongEntity(row: $0.row) }
		}

		func suggestedEntities() async throws -> [SongEntity] {
			try await LibraryCatalog.shared.tracks()
				.sorted { $0.addedAt > $1.addedAt }
				.prefix(25)
				.map(SongEntity.init(row:))
		}

		func reindexEntities(for identifiers: [SongEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
			let songs = try await self.entities(for: identifiers)
			try await CSSearchableIndex(name: SpotlightIndexer.indexName).indexAppEntities(songs)
		}

		func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
			await SpotlightIndexer.shared.syncNow()
		}
	}
}
