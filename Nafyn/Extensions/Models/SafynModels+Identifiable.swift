// Made by Lumaa

import Foundation
import Safyn

// Safyn's paginated-list models are `Codable, Sendable, Hashable` but not `Identifiable` — `Paginator`
// needs `Identifiable` to diff/append pages and drive `ForEach`/`List` without a separate `id:` keypath.

extension AlbumRow: @retroactive Identifiable {}
extension MediaRow: @retroactive Identifiable {}
extension PlaylistRow: @retroactive Identifiable {}
extension NafynRequest: @retroactive Identifiable {}
extension NafynUser: @retroactive Identifiable {}

extension RankedEntity: @retroactive Identifiable {
	public var id: String { "\(self.entityType.rawValue)-\(self.entityId)-\(self.rank)" }
}

extension ReplayEntry: @retroactive Identifiable {
	public var id: String { "\(self.position)-\(self.trackId)" }
}

extension PlaylistEntry: @retroactive Identifiable {
	public var id: String { self.entryId }
}

extension LibraryMediaEntry: @retroactive Identifiable {
	public var id: String { self.media.id }
}
