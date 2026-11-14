// Made by Lumaa

import SwiftUI
import WebKit
import Safyn

/// What a track or album is called, to find it on other services. Nafyn knows no Spotify/Deezer/... IDs, so every link
/// is a search for "artist title" there (the same links as the web app's `app/utils/externalLinks.ts`).
struct ExternalShareItem: Hashable {
	let title: String
	let artist: String?

	var query: String {
		[self.artist, self.title]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}

enum ExternalService: String, CaseIterable, Identifiable {
	case spotify, appleMusic, deezer, youtube, youtubeMusic

	var id: String { self.rawValue }

	/// The services' own names, never translated.
	var name: String {
		switch self {
			case .spotify: "Spotify"
			case .appleMusic: "Apple Music"
			case .deezer: "Deezer"
			case .youtube: "YouTube"
			case .youtubeMusic: "YouTube Music"
		}
	}

	func searchURL(for query: String) -> URL? {
		let path = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?&#"))) ?? ""
		let value = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? ""
		return switch self {
			case .spotify: URL(string: "https://open.spotify.com/search/\(path)")
			// no storefront in the path: Apple Music opens the person's own
			case .appleMusic: URL(string: "https://music.apple.com/search?term=\(value)")
			case .deezer: URL(string: "https://www.deezer.com/search/\(path)")
			case .youtube: URL(string: "https://www.youtube.com/results?search_query=\(value)")
			case .youtubeMusic: URL(string: "https://music.youtube.com/search?q=\(value)")
		}
	}
}

/// "Open on" > one search link per service, for a track or album's menu ("View" category): a web view in a sheet
/// (DESIGN.md "Links": never Safari directly). Not sharing: DESIGN.md "Sharing" puts a private item (a library
/// track or album) out of reach of "Share", and shares an item's own link - see ``CatalogShareMenu``.
struct ExternalLinkMenuItems: View {
	let item: ExternalShareItem

	var body: some View {
		let query = self.item.query
		if !query.isEmpty {
			Menu {
				ForEach(ExternalService.allCases) { service in
					if let url = service.searchURL(for: query) {
						Button {
							PlayerEngine.shared.isExpanded = false
							Navigator.shared.sheet = Navigator.Paths.web(url: url)
						} label: {
							Label(service.name, systemImage: "arrow.up.forward.app")
						}
						.tint(Color.primary)
					}
				}
			} label: {
				Label(String(localized: "open-on"), systemImage: "arrow.up.forward.app")
			}
			.tint(Color.primary)
		}
	}
}

/// "Share" for a catalog track or album (not private: nobody's library): its link on this Nafyn server or its image
/// (iOS only, 9:16), both through `ShareLink` (DESIGN.md "Sharing"). `path` is the item's page (`/t/<id>`, `/a/<id>`).
struct CatalogShareMenu: View {
	@Environment(\.server) private var server: NafynServer?

	let path: String
	let title: String
	let onShareImage: () -> Void

	var body: some View {
		Menu {
			if let url = self.server?.instance.baseURL.appending(path: self.path) {
				ShareLink(item: url, subject: Text(self.title)) {
					Label(String(localized: "share-link"), systemImage: "link")
				}
				.tint(Color.primary)
			}

			Button {
				self.onShareImage()
			} label: {
				Label(String(localized: "share-as-image"), systemImage: "photo")
			}
			.tint(Color.primary)
		} label: {
			Label(String(localized: "share"), systemImage: "square.and.arrow.up")
		}
		.tint(Color.primary)
	}
}

/// A web page in a sheet (DESIGN.md "Links"), with a Close button.
struct WebSheet: View {
	let url: URL

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			WebView(url: self.url)
				.ignoresSafeArea(edges: .bottom)
				.navigationTitle(self.url.host() ?? "")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button {
							self.dismiss()
						} label: {
							Label(String(localized: "close"), systemImage: "xmark")
								.labelStyle(.iconOnly)
						}
						.tint(Color.primary)
					}
				}
		}
		.sheetBackground()
	}
}
