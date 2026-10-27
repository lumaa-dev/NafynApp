// Made by Lumaa

import Foundation
import Safyn

/// Defensive decoding for `Album.get(aid:)`: if a single track entry in the response is missing a
/// required field (seen in practice as a `keyNotFound("id")` decoding failure when opening an album),
/// drop just that track instead of failing the whole album screen.
private struct LenientTrackInfo: Decodable {
	let id: String?
	let title: String?
	let trackNumber: Double?
	let discNumber: Double?
	let duration: Double?
	let releaseDate: Date?
	let released: Bool?
	let inLibrary: Bool?
	let requested: Bool?
	let mediaId: String?

	var resolved: TrackInfo? {
		guard let id, let title, let trackNumber, let duration, let released, let inLibrary, let requested else { return nil }
		// a track already in the library is playable, so it is released whatever MusicBrainz says
		return TrackInfo(id: id, title: title, trackNumber: trackNumber, discNumber: discNumber ?? 1, duration: duration, releaseDate: releaseDate, released: released || inLibrary, inLibrary: inLibrary, requested: requested, mediaId: mediaId)
	}
}

private struct LenientAlbumDetail: Decodable {
	let id: String
	let releaseId: String
	let title: String
	let artist: ArtistRef
	let type: AlbumKind?
	let coverArt: String?
	let releaseDate: Date?
	let releaseDatePrecision: ReleaseDatePrecision?
	let released: Bool?
	let subscribed: Bool?
	let requested: Bool?
	let inLibrary: Bool?
	let description: String?
	let label: String?
	let discs: [DiscInfo]?
	let tracks: [LenientTrackInfo]
	let imageColors: [String]?
	let textColor: String?

	var resolved: AlbumDetail {
		AlbumDetail(id: id, releaseId: releaseId, title: title, artist: artist, type: type, coverArt: coverArt, releaseDate: releaseDate, releaseDatePrecision: releaseDatePrecision, released: released ?? true, subscribed: subscribed ?? false, requested: requested ?? false, inLibrary: inLibrary ?? false, description: description, label: label, discs: discs ?? [], tracks: tracks.compactMap { $0.resolved }, imageColors: imageColors ?? [], textColor: textColor ?? "#FFFFFF")
	}
}

extension NafynServer {
	/// `Album.get(aid:)`, tolerant of individual malformed track entries.
	func fetchAlbumDetail(aid: String) async throws -> AlbumDetail {
		let data = try await self.sendRaw(Album.get(aid: aid))
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			return try decoder.decode(LenientAlbumDetail.self, from: data).resolved
		} catch {
			throw NafynError.decoding(String(describing: error))
		}
	}
}
