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
		let stack = self.currentPath[self.currentTab] ?? []
		self.currentPath[self.currentTab] = Self.folded(stack + [path], pushed: true)
	}

	/// Swaps the screen on top of a tab's stack for another one in place, without the push animation (the catalog /
	/// library versions of an album or a track, ``MediaVersionPicker``). `isCurrent` says which path is the screen
	/// being replaced (it may have been opened as a recently played entry); nothing happens when no tab shows it.
	func replaceTop(where isCurrent: (Navigator.Paths) -> Bool, with replacement: Navigator.Paths) {
		let tabs = [self.currentTab] + self.currentPath.keys.filter { $0 != self.currentTab }
		guard let tab = tabs.first(where: { self.currentPath[$0]?.last.map(isCurrent) ?? false }) else { return }
		var transaction = Transaction()
		transaction.disablesAnimations = true
		withTransaction(transaction) {
			self.currentPath[tab] = Array((self.currentPath[tab] ?? []).dropLast()) + [replacement]
		}
	}

	/// The binding for a tab's `NavigationStack(path:)`. Pushes that don't go through ``send(to:)`` (a
	/// `NavigationLink(value:)`) get the same rule: a path that is already in the stack pops back to it.
	func path(for tab: Navigator.Tabs) -> Binding<[Navigator.Paths]> {
		Binding(
			get: { self.currentPath[tab] ?? [] },
			set: { newValue in
				let old = self.currentPath[tab] ?? []
				self.currentPath[tab] = Self.folded(newValue, pushed: newValue.count > old.count)
			}
		)
	}

	/// `stack` with its last path folded back onto an earlier copy of itself, when it was just pushed.
	private static func folded(_ stack: [Navigator.Paths], pushed: Bool) -> [Navigator.Paths] {
		guard pushed, let last = stack.last, let existing = stack.dropLast().firstIndex(of: last) else { return stack }
		return Array(stack.prefix(through: existing))
	}

	enum Tabs: String, Hashable, Viewable {
		case home
		case library
		case requests
		case search

		var label: String {
			switch self {
				case .home:
					String(localized: "discover")
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
					"square.grid.2x2.fill"
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
		/// `release`: open the album on that release (a Deluxe or Remaster edition) instead of the standard one.
		case album(id: String, release: String? = nil)
		case artist(id: String)
		case track(id: String)
		case playlist(id: String)
		case libraryAlbum(id: String)
		case libraryTrack(id: String)
		case recentTrack(mediaId: String, mbid: String)
		case recentAlbum(id: String)
		case myTracks
		case myAlbums
		case myPlaylists
		case everyoneLibrary
		case settings
		case userProfile
		case settingsAccounts
		case settingsStorage
		case settingsDownloads
		case settingsPrivacy
		case settingsAppearance
		case settingsEqualizer
		case settingsInsights
		case settingsUnity
		case settingsNotifications
		case settingsWebhooks
		case settingsListenBrainz
		case users
		case musicYear(year: Int?)
		case monthlyInsights(month: String?)
		case insightsTop(type: RankedEntityKind, period: String, year: Int?, month: String?)
		case replayMix(year: String?)
		/// A personalized mix (Discover).
		case mix(id: String)
		case yearComparison
		case addToPlaylist(mediaIds: [String])
		case changeAlbum(trackId: String)
		case editMetadata(trackIds: [String])
		/// A web page in a sheet (DESIGN.md "Links": never Safari directly).
		case web(url: URL)
		/// Share a catalog track or album (`path`: `t/<id>` or `a/<id>`) as a link or an image.
		case shareCatalog(path: String, title: String, subtitle: String?, coverURL: URL?)

		/// The destination screen. A path opened from a ``MusicCard`` zooms out of that card's cover; the
		/// ones shown as a sheet never zoom.
		var view: AnyView {
			switch self {
				case .addToPlaylist, .changeAlbum, .web, .editMetadata, .shareCatalog:
					self.screen
				default:
					AnyView(CardZoomDestination(path: self) { self.screen })
			}
		}

		private var screen: AnyView {
			switch self {
				case .album(let id, let release):
					AnyView(AlbumDetailView(albumId: id, releaseId: release))
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
				case .recentTrack(let mediaId, let mbid):
					AnyView(RecentTrackView(mediaId: mediaId, mbid: mbid))
				case .recentAlbum(let id):
					AnyView(RecentAlbumView(albumId: id))
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
				case .userProfile:
					AnyView(UserProfileView())
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
				case .settingsEqualizer:
					AnyView(EqualizerSettingsView())
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
				case .settingsListenBrainz:
					AnyView(SettingsSectionScreen(title: String("ListenBrainz")) {
						ListenBrainzSettingsSection()
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
				case .mix(let id):
					AnyView(MixDetailView(mixId: id))
				case .yearComparison:
					AnyView(YearComparisonView())
				case .addToPlaylist(let mediaIds):
					AnyView(AddToPlaylistSheet(mediaIds: mediaIds))
				case .changeAlbum(let trackId):
					AnyView(ChangeAlbumSheet(trackId: trackId))
				case .web(let url):
					AnyView(WebSheet(url: url))
				case .editMetadata(let trackIds):
					AnyView(MediaEditSheet(trackIds: trackIds))
				case .shareCatalog(let path, let title, let subtitle, let coverURL):
					AnyView(ShareCatalogSheet(path: path, title: title, subtitle: subtitle, coverURL: coverURL))
			}
		}

		var id: String { String(describing: self) }
	}
}
