// Made by Lumaa

import Foundation
import Safyn

/// Finds what a person said among the user's own music. Siri, Shortcuts and the entity queries all go through
/// here, so "Put The Vows on Nafyn", "play vows by kate bush" and "Joue Dopamine Chamber" are matched the same
/// way: without caring for case, accents or punctuation, in any language.
nonisolated enum LibrarySearch {
	/// Lower case, no accents, no punctuation, single spaces.
	static func normalize(_ text: String) -> String {
		let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
		let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
		return words.joined(separator: " ")
	}

	/// How well `fields` answer `query`: 0 is an exact name, 1 a name that contains the query or is contained
	/// in it ("the vows by kate bush"), 2 every word of the query appears somewhere. `nil` is no match.
	static func score(_ query: String, in fields: [String?]) -> Int? {
		let query = self.normalize(query)
		guard !query.isEmpty else { return nil }

		let names = fields.compactMap { $0 }.map(self.normalize).filter { !$0.isEmpty }
		var best: Int?

		for name in names {
			if name == query {
				return 0
			} else if name.contains(query) || (name.count >= 3 && " \(query) ".contains(" \(name) ")) {
				best = min(best ?? 1, 1)
			}
		}
		if best != nil { return best }

		let haystack = " " + names.joined(separator: " ") + " "
		let words = query.split(separator: " ")
		return words.allSatisfy { haystack.contains($0) } ? 2 : nil
	}

	/// The rows with a match, best first (stable for equal scores).
	private static func ranked<Row>(_ rows: [Row], query: String, fields: (Row) -> [String?]) -> [(score: Int, row: Row)] {
		rows.enumerated()
			.compactMap { index, row in self.score(query, in: fields(row)).map { (score: $0, index: index, row: row) } }
			.sorted { ($0.score, $0.index) < ($1.score, $1.index) }
			.map { (score: $0.score, row: $0.row) }
	}

	static func tracks(_ rows: [MediaRow], matching query: String) -> [(score: Int, row: MediaRow)] {
		self.ranked(rows, query: query) { [$0.title, $0.artistName, $0.album, "\($0.title) \($0.artistName)"] }
	}

	static func albums(_ rows: [AlbumRow], matching query: String) -> [(score: Int, row: AlbumRow)] {
		self.ranked(rows, query: query) { [$0.title, $0.artistName, "\($0.title) \($0.artistName)"] }
	}

	static func artists(_ names: [String], matching query: String) -> [(score: Int, row: String)] {
		self.ranked(names, query: query) { [$0] }
	}

	static func playlists(_ rows: [PlaylistRow], matching query: String) -> [(score: Int, row: PlaylistRow)] {
		self.ranked(rows, query: query) { [$0.title] }
	}

	/// The artist names of the library, once each.
	static func artistNames(in tracks: [MediaRow]) -> [String] {
		var seen: Set<String> = []
		return tracks.compactMap { track in
			seen.insert(self.normalize(track.artistName)).inserted ? track.artistName : nil
		}
		.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}
}
