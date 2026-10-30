// Made by Lumaa

import AppIntents
import Foundation

/// How "Find Library Tracks" orders its results.
enum TrackSortOption: String, AppEnum {
	case title
	case artist
	case album
	case dateAdded
	case duration
	case releaseDate

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Track Sort")

	static let caseDisplayRepresentations: [TrackSortOption: DisplayRepresentation] = [
		.title: "Title",
		.artist: "Artist",
		.album: "Album",
		.dateAdded: "Date Added",
		.duration: "Duration",
		.releaseDate: "Release Date",
	]
}

/// How "Find Library Albums" orders its results.
enum AlbumSortOption: String, AppEnum {
	case title
	case artist
	case dateAdded
	case trackCount
	case duration
	case releaseDate

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album Sort")

	static let caseDisplayRepresentations: [AlbumSortOption: DisplayRepresentation] = [
		.title: "Title",
		.artist: "Artist",
		.dateAdded: "Date Added",
		.trackCount: "Track Count",
		.duration: "Duration",
		.releaseDate: "Release Date",
	]
}

/// How "Get Playlists" orders its results.
enum PlaylistSortOption: String, AppEnum {
	case title
	case dateUpdated

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playlist Sort")

	static let caseDisplayRepresentations: [PlaylistSortOption: DisplayRepresentation] = [
		.title: "Title",
		.dateUpdated: "Date Updated",
	]
}
