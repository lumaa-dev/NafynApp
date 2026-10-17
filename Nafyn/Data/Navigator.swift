// Made by Lumaa

import SwiftUI
import Safyn

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

	/// Pushes `path` onto the current tab's stack. If `path` is already somewhere in that stack, everything
	/// after it is dropped instead of appending a duplicate — so re-sending an already-visited path pops
	/// back to it rather than growing the stack with a second copy.
	func send(to path: Navigator.Paths) {
		var stack = self.currentPath[self.currentTab] ?? []
		if let existingIndex = stack.firstIndex(of: path) {
			stack.removeSubrange((existingIndex + 1)...)
		} else {
			stack.append(path)
		}
		self.currentPath[self.currentTab] = stack
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
		case settingsAccounts
		case settingsStorage
		case settingsDownloads
		case settingsPrivacy
		case settingsAppearance
		case settingsInsights
		case settingsUnity
		case settingsNotifications
		case settingsWebhooks
		case users
		case musicYear(year: Int?)
		case monthlyInsights(month: String?)
		case insightsTop(type: RankedEntityKind, period: String, year: Int?, month: String?)
		case replayMix(year: String?)
		case yearComparison
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
				case .settingsAccounts:
					AnyView(SettingsSectionScreen(title: String(localized: "accounts")) {
						AccountsSettingsSection()
					})
				case .settingsStorage:
					AnyView(SettingsSectionScreen(title: String(localized: "storage")) {
						StorageSettingsSection()
					})
				case .settingsDownloads:
					AnyView(SettingsSectionScreen(title: String(localized: "downloads")) {
						DownloadsSettingsSection()
					})
				case .settingsPrivacy:
					AnyView(SettingsSectionScreen(title: String(localized: "privacy")) {
						PrivacySettingsSection()
					})
				case .settingsAppearance:
					AnyView(SettingsSectionScreen(title: String(localized: "appearance")) {
						AppearanceSettingsSection()
					})
				case .settingsInsights:
					AnyView(SettingsSectionScreen(title: String(localized: "insights")) {
						InsightsSettingsSection()
					})
				case .settingsUnity:
					AnyView(SettingsSectionScreen(title: String(localized: "unity")) {
						UnitySettingsSection()
					})
				case .settingsNotifications:
					AnyView(SettingsSectionScreen(title: String(localized: "notifications")) {
						NotificationsSettingsSection()
					})
				case .settingsWebhooks:
					AnyView(SettingsSectionScreen(title: String(localized: "webhooks")) {
						InstanceWebhooksSettingsSection()
					})
				case .users:
					AnyView(UsersAdminView())
				case .musicYear(let year):
					AnyView(MusicYearView(year: year))
				case .monthlyInsights(let month):
					AnyView(MonthlyInsightsView(month: month))
				case .insightsTop(let type, let period, let year, let month):
					AnyView(InsightsTopListView(type: type, period: period, year: year, month: month))
				case .replayMix(let year):
					AnyView(ReplayMixView(year: year))
				case .yearComparison:
					AnyView(YearComparisonView())
				case .addToPlaylist(let mediaIds):
					AnyView(AddToPlaylistSheet(mediaIds: mediaIds))
			}
		}

		var id: String { String(describing: self) }
	}
}
