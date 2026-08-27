// Made by Lumaa

import SwiftUI

@Observable
final class Navigator {
	static let shared: Navigator = .init()

	public var currentTab: Navigator.Tabs
	public var sheet: (any Screeny)?
	public var currentPath: [Navigator.Tabs : [Navigator.Paths]]

	private init() {
		// `.home` has no actual tab in `RootView`'s `TabView` (it's a defined-but-unused case, matching
		// the web app's lack of a dashboard page) — defaulting `currentTab` to it meant the very first
		// `send(to:)` before the user manually switches tabs pushed onto `currentPath[.home]`, a path
		// nobody's `NavigationStack` was bound to, so the very first tap on any nav button silently did
		// nothing until the user switched tabs once (which corrects `currentTab` via the TabView binding).
		self.currentTab = .library
		self.currentPath = [:]
		self.sheet = nil
	}

	func send(to path: Navigator.Paths) {
		if self.currentPath[self.currentTab] != nil {
			self.currentPath[self.currentTab]?.append(path)
		} else {
			self.currentPath[self.currentTab] = [path]
		}
	}

	enum Tabs: String, Hashable, Viewable {
		case home
		case library
		case requests
		case search

		var label: String {
			switch self {
				case .home:
					String(localized: "home")
				case .library:
					String(localized: "library")
				case .requests:
					String(localized: "requests")
				case .search:
					String(localized: "search")
			}
		}

		var symbol: String {
			switch self {
				case .home:
					"house"
				case .library:
					"book"
				case .requests:
					"tray.and.arrow.down"
				case .search:
					"magnifyingglass"
			}
		}
	}

	enum Paths: Screeny, Hashable, Identifiable {
		case album(id: String)
		case artist(id: String)
		case track(id: String)
		case playlist(id: String)
		case libraryAlbum(id: String)
		case libraryTrack(id: String)
		case myTracks
		case myAlbums
		case myPlaylists
		case everyoneLibrary
		case settings
		case users
		case addToPlaylist(mediaIds: [String])

		var view: AnyView {
			switch self {
				case .album(let id):
					AnyView(AlbumDetailView(albumId: id))
				case .artist(let id):
					AnyView(ArtistDetailView(artistId: id))
				case .track(let id):
					AnyView(TrackDetailView(trackId: id))
				case .playlist(let id):
					AnyView(PlaylistDetailView(playlistId: id))
				case .libraryAlbum(let id):
					AnyView(LibraryAlbumDetailView(albumId: id))
				case .libraryTrack(let id):
					AnyView(LibraryTrackDetailView(trackId: id))
				case .myTracks:
					AnyView(MyTracksView())
				case .myAlbums:
					AnyView(MyAlbumsView())
				case .myPlaylists:
					AnyView(MyPlaylistsView())
				case .everyoneLibrary:
					AnyView(AllLibraryView())
				case .settings:
					AnyView(SettingsView())
				case .users:
					AnyView(UsersAdminView())
				case .addToPlaylist(let mediaIds):
					AnyView(AddToPlaylistSheet(mediaIds: mediaIds))
			}
		}

		var id: String { String(describing: self) }
	}
}
