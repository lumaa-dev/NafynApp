// Made by Lumaa

import SwiftUI
import WebKit

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

/// "Open on YouTube" and "Share" > one search link per service, for a track or album's menu ("View" category).
/// DESIGN.md "Links": a link opens in a sheet with a web view, not in Safari; "Sharing": one item at a time, through
/// `ShareLink`.
struct ExternalLinkMenuItems: View {
	let item: ExternalShareItem

	var body: some View {
		let query = self.item.query
		if !query.isEmpty {
			if let youtube = ExternalService.youtube.searchURL(for: query) {
				Button {
					PlayerEngine.shared.isExpanded = false
					Navigator.shared.sheet = Navigator.Paths.web(url: youtube)
				} label: {
					Label(String(localized: "open-on-youtube"), systemImage: "play.rectangle")
				}
				.tint(Color.primary)
			}

			Menu {
				ForEach(ExternalService.allCases) { service in
					if let url = service.searchURL(for: query) {
						ShareLink(item: url, subject: Text(self.item.title)) {
							Label(service.name, systemImage: "link")
						}
						.tint(Color.primary)
					}
				}
			} label: {
				Label(String(localized: "share"), systemImage: "square.and.arrow.up")
			}
			.tint(Color.primary)
		}
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
