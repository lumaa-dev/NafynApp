// Made by Lumaa

import SwiftUI
import Safyn

struct MusicCard: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	@State private var toast = ToastState()

	var entry: MusicCardEntry
	var type: Self.ViewType

	/// Adds a destructive "Delete" to the card's context menu; the owner confirms and performs the delete.
	var onDelete: (() -> Void)?

	init(_ entry: MusicCardEntry, type: Self.ViewType = .highlight, onDelete: (() -> Void)? = nil) {
		self.entry = entry
		self.type = type
		self.onDelete = onDelete
	}

	var body: some View {
		Group {
			switch self.type {
				case .highlight:
					self.highlight()
				case .row:
					self.row()
			}
		}
		// pointer lift on iPad (and the Duo with a mouse); no effect with touch alone
		.contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10.0))
		.hoverEffect()
		.contextMenu {
			self.menu
		}
		.toast(self.toast)
	}

	@ViewBuilder
	private var menu: some View {
		if self.entry.isPlayable {
			ControlGroup {
				Button {
					self.play(shuffle: false)
				} label: {
					Label(String(localized: "play"), systemImage: "play.fill")
				}
				.tint(Color.primary)

				Button {
					self.play(shuffle: true)
				} label: {
					Label(String(localized: "shuffle"), systemImage: "shuffle")
				}
				.tint(Color.primary)
			}
		}

		if let onDelete = self.onDelete {
			Button(role: .destructive) {
				onDelete()
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
			.disabled(NetworkMonitor.shared.isOffline)
		}
	}

	private func play(shuffle: Bool) {
		let entry = self.entry
		let server = self.server

		Task {
			do {
				var (queue, context) = try await entry.playbackQueue(server: server)
				guard !queue.isEmpty else { return }
				if shuffle {
					queue.shuffle()
				}
				PlaybackSource.play(queue[0], queue: queue, recordContext: context)
			} catch {
				self.toast.failure(error)
			}
		}
	}

	/// Fills the width its container proposes (an adaptive grid cell, see ``GridItem/musicCard``) with a
	/// square cover, instead of a fixed 170pt box that left gaps in wider windows.
	@ContentBuilder
	func highlight() -> some View {
		// a card is up to 220pt wide (660px at 3x): 500px covers a phone's two columns, wider windows get 1000px
		let coverSize: UInt16 = self.horizontalSizeClass == .regular ? 1000 : 500

		VStack(alignment: .leading) {
			Color.clear
				.aspectRatio(1.0, contentMode: .fit)
				.overlay {
					CoverImage(url: self.entry.coverURL(server: self.server, size: coverSize), cornerRadius: 0)
				}
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
		.frame(maxWidth: .infinity, alignment: .topLeading)
	}

	@ContentBuilder
	func row() -> some View {
		HStack {
			Group {
				CoverImage(url: self.entry.coverURL(server: self.server), cornerRadius: 0)
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
	/// `size` (250 / 500 / 1000) only applies to server cover paths, not to playlist images or artist photos.
	func coverURL(server: NafynServer?, size: UInt16? = nil) -> URL? {
		switch self {
			case .recentlyPlayed(let entry):
				if entry.type == .playlist {
					return Self.playlistImageURL(pid: entry.refId, server: server)
				}
				return Self.artURL(entry.coverArt, size: size)
			case .album(let album):
				return Self.artURL(album.coverArt, size: size)
			case .media(let media):
				return Self.artURL(media.coverArt, size: size)
			case .playlist(let playlist):
				guard playlist.image != nil else { return nil }
				return Self.playlistImageURL(pid: playlist.id, server: server)
			case .info(let info):
				return Self.artURL(info.coverArt, size: size)
			case .artist(let artist):
				return artist.image.flatMap { URL(string: $0) }
		}
	}

	private static func artURL(_ path: String?, size: UInt16?) -> URL? {
		guard let path else { return nil }
		if let size, path.contains("/art/") {
			return path.coverArtURL(size: size)
		}
		return URL(string: path)
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
