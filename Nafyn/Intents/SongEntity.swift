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

	var title: String
	var artistName: String
	var composerName: String?
	var albumTitle: String?
	var artists: [ArtistEntity]
	var album: AlbumEntity?
	var composers: [ArtistEntity]
	var internationalStandardRecordingCode: String?

	@Property(title: "Duration")
	var duration: Measurement<UnitDuration>

	@Property(title: "Date Added")
	var dateAdded: Date

	@Property(title: "Track Number")
	var trackNumber: Int?

	@Property(title: "Release Date")
	var releaseDate: Date?

	var coverArt: String?

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(self.title)",
			subtitle: "\(self.artistName)"
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
		self.coverArt = row.coverArt
	}

	struct SongEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
		typealias Entity = SongEntity
		func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
			let wanted = Set(identifiers)
			return try await LibraryCatalog.shared.tracks().filter { wanted.contains($0.id) }.map(SongEntity.init(row:))
		}

		func entities(matching string: String) async throws -> [SongEntity] {
			try await LibraryCatalog.shared.tracks()
				.filter {
					$0.title.localizedCaseInsensitiveContains(string)
						|| $0.artistName.localizedCaseInsensitiveContains(string)
						|| ($0.album?.localizedCaseInsensitiveContains(string) ?? false)
				}
				.map(SongEntity.init(row:))
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
