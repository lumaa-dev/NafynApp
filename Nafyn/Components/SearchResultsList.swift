// Made by Lumaa

import SwiftUI
import Safyn

/// The results of a search as ONE list (DESIGN.md "Search"): track rows, album rows and artist rows, the most
/// likely answer on top and the least likely at the bottom. The kind of each row is written in its second line,
/// never told by the shape of the cover alone.
struct SearchResultsList: View {
	let result: SearchResult

	var body: some View {
		let entries = result.rankedEntries

		if entries.isEmpty {
			Text("no-results")
				.font(DTFont.system(18))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				.frame(maxWidth: .infinity)
				.padding(.top, 40)
		} else {
			LazyVStack(spacing: 12) {
				ForEach(entries) { entry in
					self.row(entry)
				}
			}
		}
	}

	@ViewBuilder
	private func row(_ entry: SearchEntry) -> some View {
		if let card = entry.card {
			let content = MusicCard(card, type: .row, subtitle: entry.subtitle)
			if let destination = card.destination {
				NavigationLink(value: destination) {
					content
				}
				.buttonStyle(.plain)
			} else {
				content
			}
		}
	}
}

extension SearchResult {
	/// The ranked list the server sent; from a server older than the list, the three kinds one after the other.
	var rankedEntries: [SearchEntry] {
		if !self.results.isEmpty { return self.results }
		return self.albums.map { SearchEntry(kind: .album, relevance: 0, media: $0) }
			+ self.artists.map { SearchEntry(kind: .artist, relevance: 0, artist: $0) }
			+ self.tracks.map { SearchEntry(kind: .track, relevance: 0, media: $0) }
	}
}

extension SearchEntry {
	/// The card this row is made of; `nil` for a kind this app doesn't know yet.
	var card: MusicCardEntry? {
		switch self.kind {
			case .track, .album:
				self.media.map { .info($0) }
			case .artist:
				self.artist.map { .artist($0) }
			case .unknown:
				nil
		}
	}

	/// "Track · Artist", "Album · Artist", "EP · Artist", "Artist": what the row is, then who it is by.
	var subtitle: String? {
		switch self.kind {
			case .track:
				[String(localized: "search-kind-track"), self.media?.artist.name].compactMap { $0 }.joined(separator: " · ")
			case .album:
				[self.media?.type == .ep ? String(localized: "search-kind-ep") : String(localized: "search-kind-album"), self.media?.artist.name].compactMap { $0 }.joined(separator: " · ")
			case .artist:
				[String(localized: "search-kind-artist"), self.artist?.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
			case .unknown:
				nil
		}
	}
}
