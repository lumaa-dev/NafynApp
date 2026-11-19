// Made by Lumaa

import SwiftUI
import WebKit
import SafariServices
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
/// track or album) out of reach of "Share", and shares an item's own link - see ``CatalogShareButton``.
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

/// "Share" for a catalog track or album, and for a library one (what is shared is its catalog page, never the
/// private library entry): opens ``ShareCatalogSheet``, which shares the link on this Nafyn server or the image
/// (iOS only, 9:16), both through `ShareLink` (DESIGN.md "Sharing"). `path` is the item's page (`t/<id>`, `a/<id>`).
struct CatalogShareButton: View {
	let path: String
	let title: String
	var subtitle: String? = nil
	var coverURL: URL? = nil

	var body: some View {
		Button {
			PlayerEngine.shared.isExpanded = false
			Navigator.shared.sheet = Navigator.Paths.shareCatalog(path: self.path, title: self.title, subtitle: self.subtitle, coverURL: self.coverURL)
		} label: {
			Label(String(localized: "share"), systemImage: "square.and.arrow.up")
		}
		.tint(Color.primary)
	}
}

extension OpenURLAction {
	/// DESIGN.md "Links": a web link (a `Link`, a link in markdown text) opens in the ``Navigator/Paths/web(url:)``
	/// sheet, never in Safari directly. Any other scheme (the Settings app, `mailto:`) still goes to the system.
	/// Set once on the tabs in `RootView`, so a new `Link` needs nothing more.
	static let nafynWebSheet = OpenURLAction { url in
		guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .systemAction }
		Navigator.shared.sheet = Navigator.Paths.web(url: url)
		return .handled
	}
}

struct WebSheet: UIViewControllerRepresentable {
	/// The URL to be opened in the Safari view.
	let url: URL

	/// Creates and returns a new instance of SFSafariViewController.
	/// - Parameter context: The context in which the Safari view controller is being created.
	/// - Returns: An instance of SFSafariViewController with the specified URL.
	func makeUIViewController(context: UIViewControllerRepresentableContext<WebSheet>) -> SFSafariViewController {
		let safari = SFSafariViewController(url: url)
		safari.dismissButtonStyle = .close
		safari.modalPresentationStyle = .overCurrentContext

		return safari
	}

	/// Updates the Safari view controller when needed.
	/// - Parameters:
	///   - uiViewController: The existing SFSafariViewController instance.
	///   - context: The context in which the Safari view controller is being updated.
	func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<WebSheet>) {

	}
}
