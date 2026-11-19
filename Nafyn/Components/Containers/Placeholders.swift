// Made by Lumaa

import Foundation
import Safyn

// One placeholder value per screen loaded through `AsyncContentView` (DESIGN.md "Skeleton loading"): the screen is
// drawn with it, redacted, while the real one loads. Only the shape matters - typical lengths of text, a few rows -
// and nothing in here may lead anywhere: no real ID, no cover URL (a redacted `CoverImage` loads nothing anyway).

private enum Placeholder {
	static let id = "placeholder"
	static let title = "Placeholder title"
	static let artist = "Artist name"

	static func mediaRow(_ index: Int) -> MediaRow {
		let titles = ["Placeholder title", "A longer placeholder title", "Placeholder", "Title of a track", "Another placeholder"]
		return MediaRow(
			id: "\(Self.id)-\(index)", musicbrainzId: "", title: titles[index % titles.count], artistName: Self.artist, artistMbid: nil,
			album: Self.title, albumId: Self.id, albumType: .album, coverArt: nil, releaseDate: nil, duration: 215, label: nil,
			fingerprint: nil, amId: nil, fileSize: nil, addedAt: 0, trackNumber: Double(index + 1), discNumber: 1
		)
	}

	static func trackInfo(_ index: Int) -> TrackInfo {
		let row = Self.mediaRow(index)
		return TrackInfo(id: row.id, title: row.title, trackNumber: Double(index + 1), discNumber: 1, duration: 215, releaseDate: nil, released: true, inLibrary: false, requested: false, mediaId: nil)
	}

	static let user = NafynUser(id: Self.id, username: "placeholder", displayName: Self.artist)
}

extension AlbumDetail {
	static let placeholder = AlbumDetail(
		id: Placeholder.id, releaseId: Placeholder.id, title: Placeholder.title, artist: .name(Placeholder.artist), type: .album,
		coverArt: nil, releaseDate: nil, releaseDatePrecision: nil, released: true, subscribed: false, requested: false, inLibrary: false,
		description: nil, label: nil, discs: [DiscInfo(number: 1, title: nil)], tracks: (0..<10).map(Placeholder.trackInfo),
		imageColors: [], textColor: "#FFFFFF"
	)
}

extension TrackRelease {
	static let placeholder = TrackRelease(
		detail: TrackDetail(
			info: MediaInfo(id: Placeholder.id, title: Placeholder.title, artist: .name(Placeholder.artist), album: nil, type: .track, coverArt: nil, releaseDate: nil, inLibrary: false, duration: 215, label: nil),
			albumMbid: nil
		),
		released: true,
		subscribed: false,
		precision: nil
	)
}

extension LibraryTrackResponse {
	static let placeholder = LibraryTrackResponse(row: Placeholder.mediaRow(0), imageColors: [], textColor: "#FFFFFF")
}

extension LibraryAlbumResponse {
	static let placeholder = LibraryAlbumResponse(
		album: LibraryAlbumResponse.Album(
			row: AlbumRow(id: Placeholder.id, mbId: "", title: Placeholder.title, artistName: Placeholder.artist, artistMbid: nil, coverArt: nil, releaseDate: nil, duration: 0, trackCount: 10, addedAt: 0),
			imageColors: [],
			textColor: "#FFFFFF"
		),
		tracks: (0..<10).map(Placeholder.mediaRow)
	)
}

extension ArtistDetail {
	static let placeholder: ArtistDetail = {
		let release = { (index: Int) in
			MediaInfo(id: "\(Placeholder.id)-\(index)", title: Placeholder.title, artist: .name(Placeholder.artist), album: nil, type: .album, coverArt: nil, releaseDate: nil, inLibrary: false, duration: 0, label: nil)
		}
		return ArtistDetail(
			id: Placeholder.id, name: Placeholder.artist, image: nil, bio: String(repeating: "A placeholder line of the artist's biography. ", count: 4), listeners: nil,
			albums: [],
			categories: [
				ReleaseCategory(id: .album, releases: (0..<4).map { ArtistRelease(media: release($0)) }),
				ReleaseCategory(id: .single, releases: (4..<8).map { ArtistRelease(media: release($0)) })
			]
		)
	}()
}

extension PlaylistDetail {
	static let placeholder = PlaylistDetail(
		playlist: PlaylistRow(id: Placeholder.id, ownerId: Placeholder.id, title: Placeholder.title, description: nil, privacy: .private, image: nil, sortMode: .manual, createdAt: 0, updatedAt: 0),
		owner: Placeholder.user,
		members: [],
		entries: (0..<10).map { PlaylistEntry(entryId: "\(Placeholder.id)-\($0)", addedBy: Placeholder.user, position: Double($0), addedAt: 0, media: Placeholder.mediaRow($0)) },
		entriesTotal: 10,
		entriesHasMore: false,
		viewer: PlaylistDetail.Viewer(userId: nil, isOwner: false, isMember: false)
	)
}

extension MixDetail {
	/// Decoded: Safyn has no memberwise initializer for a mix. Ten familiar-looking rows.
	static let placeholder: MixDetail? = {
		let tracks = (0..<10).map { index in
			#"{"position":\#(index),"familiar":false,"confidence":0.5,"reason":{"kind":"novel","via":"collaborative"},"suggestion":{"recordingId":"placeholder-\#(index)","title":"Placeholder title","artist":"Artist name","album":null,"albumId":null,"coverArt":null,"durationMs":215000}}"#
		}
		let json = #"{"id":"placeholder","position":0,"label":{"kind":"genre","value":"placeholder"},"title":"Placeholder mix","topArtists":["Artist name","Another artist"],"trackCount":10,"familiarCount":0,"covers":[],"refreshedAt":0,"tracks":[\#(tracks.joined(separator: ","))]}"#
		return try? JSONDecoder().decode(MixDetail.self, from: Data(json.utf8))
	}()
}
