// Made by Lumaa

import SwiftUI
import Safyn

struct MusicCard: View {
	@Environment(\.server) private var server: NafynServer?

	var entry: MusicCardEntry
	var type: Self.ViewType

	init(_ entry: MusicCardEntry, type: Self.ViewType = .highlight) {
		self.entry = entry
		self.type = type
	}

	var body: some View {
		switch self.type {
			case .highlight:
				self.highlight()
			case .row:
				self.row()
		}
	}

	@ContentBuilder
	func highlight(width: CGFloat = 170.0) -> some View {
		VStack(alignment: .leading) {
			Group {
				if let url = self.entry.coverURL(server: self.server) {
					AsyncImage(url: url) { image in
						image
							.resizable()
							.aspectRatio(1.0, contentMode: .fill)
					} placeholder: {
						DTColor.surfaceSelect
					}
				} else {
					DTColor.surfaceSelect
				}
			}
			.frame(width: width, height: width)
			.clipShape(self.entry.isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10.0)))

			Text(self.entry.title)
				.font(DTFont.serif(18))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)

			if let subtitle = self.entry.subtitle {
				Text(subtitle)
					.font(DTFont.serif(16))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}
		}
		.frame(width: width, alignment: .topLeading)
	}

	@ContentBuilder
	func row() -> some View {
		HStack {
			Group {
				if let url = self.entry.coverURL(server: self.server) {
					AsyncImage(url: url) { image in
						image
							.resizable()
							.aspectRatio(1.0, contentMode: .fill)
					} placeholder: {
						DTColor.surfaceSelect
					}
				} else {
					DTColor.surfaceSelect
				}
			}
			.frame(width: 60, height: 60)
			.clipShape(self.entry.isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10.0)))

			VStack(alignment: .leading) {
				Text(self.entry.title)
					.foregroundStyle(DTColor.textPrimary)
					.font(DTFont.serif(18))
					.lineLimit(2)
					.multilineTextAlignment(.leading)

				if let subtitle = self.entry.subtitle {
					Text(subtitle)
						.font(DTFont.serif(16))
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
						.lineLimit(1)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	enum ViewType {
		case highlight
		case row
	}
}

enum MusicCardEntry: Hashable {
	case recentlyPlayed(RecentlyPlayedEntry)
	case album(AlbumRow)
	case media(MediaRow)
	case playlist(PlaylistRow)
	case info(MediaInfo)
	case artist(ArtistInfo)

	var isArtist: Bool {
		if case .artist = self { return true }
		return false
	}

	var title: String {
		switch self {
			case .recentlyPlayed(let entry):
				entry.title
			case .album(let album):
				album.title
			case .media(let media):
				media.title
			case .playlist(let playlist):
				playlist.title
			case .info(let info):
				info.title
			case .artist(let artist):
				artist.name
		}
	}

	/// The artist name, or the playlist's description when this entry is a playlist.
	var subtitle: String? {
		switch self {
			case .recentlyPlayed(let entry):
				entry.subtitle
			case .album(let album):
				album.artistName
			case .media(let media):
				media.artistName
			case .playlist(let playlist):
				playlist.description?.isEmpty == false ? playlist.description : String(localized: "playlist")
			case .info(let info):
				info.artist.name
			case .artist:
				nil
		}
	}

	/// Resolves this entry's cover art URL. Playlist covers require `server` to build the authenticated endpoint URL.
	func coverURL(server: NafynServer?) -> URL? {
		switch self {
			case .recentlyPlayed(let entry):
				if entry.type == .playlist {
					return Self.playlistImageURL(pid: entry.refId, server: server)
				}
				return entry.coverArt.flatMap { URL(string: $0) }
			case .album(let album):
				return album.coverArt.flatMap { URL(string: $0) }
			case .media(let media):
				return media.coverArt.flatMap { URL(string: $0) }
			case .playlist(let playlist):
				guard playlist.image != nil else { return nil }
				return Self.playlistImageURL(pid: playlist.id, server: server)
			case .info(let info):
				return info.coverArt.flatMap { URL(string: $0) }
			case .artist(let artist):
				return artist.image.flatMap { URL(string: $0) }
		}
	}

	private static func playlistImageURL(pid: String, server: NafynServer?) -> URL? {
		guard let server else { return nil }

		let endpoint = Playlist.image(pid: pid, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		return components.url
	}
}
