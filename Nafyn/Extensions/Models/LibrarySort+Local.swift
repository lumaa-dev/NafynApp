// Made by Lumaa

import SwiftUI
import Safyn

/// What the Tracks and Albums lists need on top of Safyn's ``LibrarySort``: a name and an icon for the menu, and
/// the same search and ordering applied locally. The server does both for what it lists; the local copy is for the
/// downloaded tracks that are merged into those lists so they stay visible offline.
extension LibrarySort {
	var title: LocalizedStringKey {
		switch self {
			case .added: "sort-added"
			case .title: "sort-title"
			case .artist: "sort-artist"
			case .released: "sort-released"
		}
	}

	var symbol: String {
		switch self {
			case .added: "clock"
			case .title: "textformat"
			case .artist: "person"
			case .released: "calendar"
		}
	}

	/// Alphabetical, ignoring case, accents and "10" < "9" numeric surprises.
	private static func alphabetical(_ a: String, _ b: String) -> ComparisonResult {
		a.localizedStandardCompare(b)
	}

	/// Newest first, undated last.
	private static func newer(_ a: Int64?, _ b: Int64?) -> Bool? {
		switch (a, b) {
			case (nil, nil): nil
			case (nil, _): false
			case (_, nil): true
			case (let a?, let b?): a == b ? nil : a > b
		}
	}

	func areInOrder(_ a: MediaRow, _ b: MediaRow) -> Bool {
		switch self {
			case .added:
				return a.addedAtDate > b.addedAtDate
			case .title:
				let result = Self.alphabetical(a.title, b.title)
				if result != .orderedSame { return result == .orderedAscending }
				return Self.alphabetical(a.artistName, b.artistName) == .orderedAscending
			case .artist:
				let byArtist = Self.alphabetical(a.artistName, b.artistName)
				if byArtist != .orderedSame { return byArtist == .orderedAscending }
				let byAlbum = Self.alphabetical(a.album ?? "", b.album ?? "")
				if byAlbum != .orderedSame { return byAlbum == .orderedAscending }
				let disc = (a.discNumber ?? 1, b.discNumber ?? 1)
				if disc.0 != disc.1 { return disc.0 < disc.1 }
				let track = (a.trackNumber ?? 0, b.trackNumber ?? 0)
				if track.0 != track.1 { return track.0 < track.1 }
				return Self.alphabetical(a.title, b.title) == .orderedAscending
			case .released:
				if let newer = Self.newer(a.releaseDate, b.releaseDate) { return newer }
				return a.addedAtDate > b.addedAtDate
		}
	}

	func areInOrder(_ a: AlbumRow, _ b: AlbumRow) -> Bool {
		switch self {
			case .added:
				return a.addedAtDate > b.addedAtDate
			case .title:
				return Self.alphabetical(a.title, b.title) == .orderedAscending
			case .artist:
				let byArtist = Self.alphabetical(a.artistName, b.artistName)
				if byArtist != .orderedSame { return byArtist == .orderedAscending }
				return Self.alphabetical(a.title, b.title) == .orderedAscending
			case .released:
				if let newer = Self.newer(a.releaseDate, b.releaseDate) { return newer }
				return a.addedAtDate > b.addedAtDate
		}
	}
}

extension MediaRow {
	/// Every word of `query` is found in the title, artist or album (accents and case ignored). Blank matches all.
	func matchesLibrarySearch(_ query: String) -> Bool {
		guard !LibrarySearch.normalize(query).isEmpty else { return true }
		return LibrarySearch.score(query, in: [self.title, self.artistName, self.album]) != nil
	}
}

extension AlbumRow {
	/// Every word of `query` is found in the album title or the artist. Blank matches all.
	func matchesLibrarySearch(_ query: String) -> Bool {
		guard !LibrarySearch.normalize(query).isEmpty else { return true }
		return LibrarySearch.score(query, in: [self.title, self.artistName]) != nil
	}
}

extension Notification.Name {
	/// Posted after a change that moves tracks around the library (a track put on another album), so the Tracks
	/// and Albums lists load again.
	static let nafynLibraryChanged = Notification.Name("nafynLibraryChanged")
}
