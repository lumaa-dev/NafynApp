// Made by Lumaa

import AppIntents
import CoreSpotlight
import Foundation
import Safyn

// The user's library as App Intents entities: what Siri, Apple Intelligence, Shortcuts and Spotlight see.
// They follow the `.audio` schemas so Siri can play them, and carry extra properties so Shortcuts shows
// them as real objects (duration, date added, …). Only owned music is ever exposed.

// MARK: - Artist

@AppEntity(schema: .audio.artist)
struct ArtistEntity: IndexedEntity {
	typealias DefaultQuery = ArtistEntityQuery
	static let defaultQuery: ArtistEntityQuery = ArtistEntityQuery()

	/// The artist's name: the library knows artists by name (MusicBrainz IDs are missing on some tracks).
	let id: String

	var name: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(self.name)")
	}

	init(name: String) {
		self.id = name
		self.name = name
	}

	struct ArtistEntityQuery: EntityQuery, EntityStringQuery {
		typealias Entity = ArtistEntity
		func entities(for identifiers: [ArtistEntity.ID]) async throws -> [ArtistEntity] {
			identifiers.map { ArtistEntity(name: $0) }
		}

		func entities(matching string: String) async throws -> [ArtistEntity] {
			let names = Set(try await LibraryCatalog.shared.tracks().map(\.artistName))
			return names
				.filter { $0.localizedCaseInsensitiveContains(string) }
				.sorted()
				.map { ArtistEntity(name: $0) }
		}

		func suggestedEntities() async throws -> [ArtistEntity] {
			Array(Set(try await LibraryCatalog.shared.tracks().map(\.artistName)).sorted().prefix(25)).map { ArtistEntity(name: $0) }
		}
	}
}
