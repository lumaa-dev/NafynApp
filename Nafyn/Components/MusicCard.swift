// Made by Lumaa

import SwiftUI
import Safyn

struct MusicCard: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.zoomNamespace) private var zoomNamespace: Namespace.ID?

	var entry: MusicCardEntry
	var type: Self.ViewType

	/// Replaces the line under the title (the artist, normally): a search row says what kind of result it is, an
	/// album's release says what sets it apart.
	var subtitle: String?

	/// Runs after the card's own "Delete" (albums and tracks in the library) succeeded, so the screen showing
	/// the card can drop it.
	var onRemoved: (() -> Void)?

	init(_ entry: MusicCardEntry, type: Self.ViewType = .highlight, subtitle: String? = nil, onRemoved: (() -> Void)? = nil) {
		self.entry = entry
		self.type = type
		self.subtitle = subtitle
		self.onRemoved = onRemoved
	}

	private var shownSubtitle: String? {
		self.subtitle ?? self.entry.subtitle
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
		// the screen this card opens zooms out of its cover while the card is on screen. Deliberately no tap
		// gesture here: one attached to a card inside a `NavigationLink` swallows the link's own tap.
		// (a card without a namespace, i.e. inside a sheet, is no zoom source)
		.onAppear { if self.zoomNamespace != nil { CardZoom.register(self.entry.destination) } }
		.onDisappear { if self.zoomNamespace != nil { CardZoom.unregister(self.entry.destination) } }
		.libraryItemMenu(
			item: self.entry.libraryItem,
			play: self.entry.isPlayable ? { [entry = self.entry, server = self.server] in try await entry.playbackQueue(server: server) } : nil,
			onRemoved: self.onRemoved
		)
	}

	private var coverShape: AnyShape {
		self.entry.isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10.0))
	}

	/// The card's picture. An artist's comes from the server's lookup (`ArtistPhoto`); the rest are plain covers.
	@ViewBuilder
	private func cover(size: UInt16?) -> some View {
		if case .artist(let artist) = self.entry {
			ArtistPhoto(artistId: artist.musicbrainzId, fallback: self.entry.coverURL(server: self.server), cornerRadius: 0)
		} else {
			CoverImage(url: self.entry.coverURL(server: self.server, size: size), cornerRadius: 0)
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
					self.cover(size: coverSize)
				}
				.clipShape(self.coverShape)
				.cardZoomSource(self.entry.destination, in: self.zoomNamespace, cornerRadius: self.entry.isArtist ? 1000 : 10)

			Text(self.entry.title)
				.font(DTFont.serif(18))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)

			if let subtitle = self.shownSubtitle {
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
				self.cover(size: nil)
			}
			.frame(width: 60, height: 60)
			.clipShape(self.coverShape)
			.cardZoomSource(self.entry.destination, in: self.zoomNamespace, cornerRadius: self.entry.isArtist ? 1000 : 10)

			VStack(alignment: .leading) {
				Text(self.entry.title)
					.foregroundStyle(DTColor.textPrimary)
					.font(DTFont.serif(18))
					.lineLimit(2)
					.multilineTextAlignment(.leading)

				if let subtitle = self.shownSubtitle {
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
	case pinned(PinnedItem)

	/// The owned album or track this card stands for, if any: what its context menu can delete.
	var libraryItem: LibraryItem? {
		switch self {
			case .pinned(let pin):
				switch pin.kind {
					case .album: .album(id: pin.refId)
					case .track: .track(id: pin.refId)
					case .playlist: nil
				}
			case .album(let album):
				.album(id: album.id)
			case .media(let media):
				.track(id: media.id)
			case .recentlyPlayed(let entry):
				switch entry.type {
					case .album: .album(id: entry.refId)
					case .track: .track(id: entry.refId)
					case .playlist: nil
				}
			case .info(let info):
				info.type != .track && info.inLibrary == true ? .album(id: info.id) : nil
			case .playlist, .artist:
				nil
		}
	}

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
			case .pinned(let pin):
				pin.title
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
			case .pinned(let pin):
				pin.kind == .playlist ? String(localized: "playlist") : pin.subtitle
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
			case .pinned(let pin):
				if pin.kind == .playlist {
					return Self.playlistImageURL(pid: pin.refId, server: server)
				}
				return Self.artURL(pin.coverArt, size: size)
		}
	}

	/// What this card pins, if it stands for something pinnable (an owned track or album, a playlist).
	var pinTarget: PinTarget? {
		switch self {
			case .recentlyPlayed(let entry):
				switch entry.type {
					case .album: .album(entry.refId)
					case .track: .track(entry.refId)
					case .playlist: .playlist(entry.destinationId)
				}
			case .album(let album):
				.album(album.id)
			case .media(let media):
				.track(media.id)
			case .playlist(let playlist):
				.playlist(playlist.id)
			case .info(let info):
				info.type != .track && info.inLibrary == true ? .album(info.id) : nil
			case .pinned(let pin):
				PinTarget(kind: pin.kind, refId: pin.refId)
			case .artist:
				nil
		}
	}

	private static func artURL(_ path: String?, size: UInt16?) -> URL? {
		guard let path else { return nil }
		if let size, path.contains("/art/") {
			return path.coverArtURL(size: size)
		}
		return URL(string: path)
	}

	static func playlistImageURL(pid: String, server: NafynServer?) -> URL? {
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
