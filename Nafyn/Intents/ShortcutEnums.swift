// Made by Lumaa

import AppIntents
import Foundation

/// What "Find in Library" looks for.
enum LibraryContentKind: String, AppEnum {
	case tracks
	case albums
	case artists
	case playlists

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Content Type")

	static let caseDisplayRepresentations: [LibraryContentKind: DisplayRepresentation] = [
		.tracks: "Tracks",
		.albums: "Albums",
		.artists: "Artists",
		.playlists: "Playlists",
	]
}

/// How "Find in Library" orders its results. What doesn't apply to the kind searched (the file size of an
/// album) falls back to the title.
enum LibrarySortOption: String, AppEnum {
	case title
	case artist
	case album
	case dateAdded
	case duration
	case releaseDate
	case trackCount
	case fileSize

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sort")

	static let caseDisplayRepresentations: [LibrarySortOption: DisplayRepresentation] = [
		.title: "Title",
		.artist: "Artist",
		.album: "Album",
		.dateAdded: "Date Added",
		.duration: "Duration",
		.releaseDate: "Release Date",
		.trackCount: "Track Count",
		.fileSize: "File Size",
	]
}

/// What "Control Playback" does.
enum PlaybackAction: String, AppEnum {
	case play
	case pause
	case togglePlayPause
	case next
	case previous

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playback Action")

	static let caseDisplayRepresentations: [PlaybackAction: DisplayRepresentation] = [
		.play: "Play",
		.pause: "Pause",
		.togglePlayPause: "Play or Pause",
		.next: "Next Track",
		.previous: "Previous Track",
	]
}

/// Who can open a playlist created from Shortcuts.
enum PlaylistVisibility: String, AppEnum {
	case `private`
	case `public`

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Visibility")

	static let caseDisplayRepresentations: [PlaylistVisibility: DisplayRepresentation] = [
		.private: "Private",
		.public: "Public",
	]
}
