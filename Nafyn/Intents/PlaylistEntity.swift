// Made by Lumaa

import AppIntents
import CoreSpotlight
import Foundation
import Safyn

// MARK: - Playlist

@AppEntity(schema: .audio.playlist)
struct PlaylistEntity: IndexedEntity {
	typealias DefaultQuery = PlaylistEntityQuery
	static let defaultQuery: PlaylistEntityQuery = PlaylistEntityQuery()

	let id: String

	@Property(title: "Title")
	var title: String

	@Property(title: "Owner")
	var owner: Owner?

	@Property(title: "intent-filter-created-by-me")
	var createdByMe: Bool?

	@Property(title: "intent-filter-curated-for-me")
	var curatedForMe: Bool?

	@Property(title: "Description")
	var summary: String?

	@Property(title: "Public")
	var isPublic: Bool

	@Property(title: "intent-property-date-updated")
	var dateUpdated: Date

	@Property(title: "intent-property-date-created")
	var dateCreated: Date

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(self.title)", subtitle: self.summary.map { "\($0)" })
	}

	@MainActor
	init(row: PlaylistRow) {
		self.id = row.id
		self.title = row.title
		self.owner = nil
		self.createdByMe = AppSession.shared.userId.map { $0 == row.ownerId }
		self.curatedForMe = false
		self.summary = row.description
		self.isPublic = row.privacy == .public
		self.dateUpdated = Date(timeIntervalSince1970: TimeInterval(row.updatedAt) / 1000)
		self.dateCreated = Date(timeIntervalSince1970: TimeInterval(row.createdAt) / 1000)
	}

	struct PlaylistEntityQuery: EntityQuery, EntityStringQuery {
		typealias Entity = PlaylistEntity
		func entities(for identifiers: [PlaylistEntity.ID]) async throws -> [PlaylistEntity] {
			let wanted = Set(identifiers)
			let rows = try await LibraryCatalog.shared.playlists().filter { wanted.contains($0.id) }
			return await MainActor.run { rows.map(PlaylistEntity.init(row:)) }
		}

		func entities(matching string: String) async throws -> [PlaylistEntity] {
			let rows = LibrarySearch.playlists(try await LibraryCatalog.shared.playlists(), matching: string).map(\.row)
			return await MainActor.run { rows.map(PlaylistEntity.init(row:)) }
		}

		func suggestedEntities() async throws -> [PlaylistEntity] {
			let rows = try await LibraryCatalog.shared.playlists()
			return await MainActor.run { rows.map(PlaylistEntity.init(row:)) }
		}
	}
}

@UnionValue
enum Owner {
	case person(IntentPerson)
	case name(String)
}
