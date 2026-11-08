// Made by Lumaa

import SwiftUI
import Safyn

enum ReleaseGridLayout {
	/// Width of a card in the row: two and a half fit a phone, so the next one is always seen peeking in.
	static let cardWidth: CGFloat = 160
}

/// A *category grid* (DESIGN.md "Category grids"): a titled group of `release`s, shown as ``MusicCard``s in ONE
/// row that scrolls sideways inside its own frame - an artist's "Albums", the releases of an album...
///
/// The screen never scrolls sideways; the covers do, and may slide under the screen's side margin while the first
/// one rests on it.
struct ReleaseGrid<Content: View>: View {
	let title: String
	var description: String?
	@ViewBuilder let content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(self.title)
					.font(DTFont.serifItalic(25))
					.foregroundStyle(DTColor.textPrimary)
					.accessibilityAddTraits(.isHeader)

				if let description, !description.isEmpty {
					Text(description)
						.font(DTFont.system(16))
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				}
			}

			ScrollView(.horizontal, showsIndicators: false) {
				LazyHStack(alignment: .top, spacing: 16) {
					self.content
				}
				// room for the outline of a selected card
				.padding(.vertical, 6)
			}
			.scrollClipDisabled()
		}
	}
}

extension ArtistRelease {
	/// Where the card of this release opens: the album, on the edition's own release when it is one.
	var destination: Navigator.Paths {
		.album(id: self.media.id, release: self.releaseId)
	}
}

extension ReleaseCategoryID {
	/// The category's name, as the grid is titled.
	var title: String {
		switch self {
			case .album: String(localized: "release-category-album")
			case .ep: String(localized: "release-category-ep")
			case .single: String(localized: "release-category-single")
			case .compilation: String(localized: "release-category-compilation")
			case .live: String(localized: "release-category-live")
			case .remix: String(localized: "release-category-remix")
			case .soundtrack: String(localized: "release-category-soundtrack")
			case .other: String(localized: "release-category-other")
		}
	}
}

extension AlbumRelease {
	/// The release as a card: its own cover and title, with what sets it apart under the title.
	var asCardEntry: MusicCardEntry {
		.info(MediaInfo(id: self.id, title: self.title, artist: .name(""), album: nil, type: .album, coverArt: self.coverArt, releaseDate: nil, inLibrary: nil, duration: 0, label: nil))
	}
}
