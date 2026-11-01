// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct RootView: View {
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.modelContext) private var modelContext
	@Query private var auth: [AuthInfo]

	@State private var isLoading: Bool = false
	@State private var server: NafynServer? = nil

	/// `AuthInfo.id` of the account `server` is currently authenticated as — compared against
	/// `defaultAuthId` to detect an account switch from Settings (see that `onChange` below).
	@State private var activeAuthId: String? = nil

	private var defaultAuthId: String? {
		self.auth.first(where: { $0.defaultAuth })?.id
	}

	/// Whether to show the library/tabs UI with `server == nil` instead of `OnboardingView`: there's at
	/// least one saved account, but `attemptLogin()` couldn't reach the server because the device itself
	/// has no route to the internet (airplane mode, no SIM, Wi-Fi off). Without this, losing connectivity
	/// at launch looked identical to never having logged in, dropping a returning user into onboarding
	/// instead of their offline-downloaded library.
	private var showOfflineLibrary: Bool {
		!self.auth.isEmpty && NetworkMonitor.shared.isOffline
	}

	@State private var onboarding: OnboardingView.OnboardingSteps = .welcome
	@Namespace private var playerZoomNamespace

	/// Scope of the card-cover → detail screen zoom (see ``CardZoom``).
	@Namespace private var cardZoomNamespace

	/// Mirrors `PlayerEngine.shared.isExpanded` as plain `@State`. The zoom transition's source
	/// geometry resolves against `MiniPlayerBar`'s `matchedTransitionSource` only when the presenting
	/// `isPresented` binding is backed by `@State` — driving `fullScreenCover` straight off an
	/// `@Observable` property (as before) makes the transition start from the screen center instead.
	@State private var isPlayerExpanded = false

	/// Mirrors `Navigator.shared.sheet != nil` as plain `@State`, for the same reason as ``isPlayerExpanded``.
	@State private var isNavigatorSheetPresented = false

	var body: some View {
		ZStack {
			self.warmup

			DTColor.background.ignoresSafeArea()

			if isLoading {
				ProgressView()
					.progressViewStyle(.circular)
					.tint(DTColor.textPrimary)
			} else if self.server != nil || self.showOfflineLibrary {
				self.tabs
				.environment(\.server, self.server)
				.environment(\.zoomNamespace, self.cardZoomNamespace)
				.fullScreenCover(isPresented: self.$isPlayerExpanded) {
					NowPlayingView(namespace: self.playerZoomNamespace)
						.environment(\.server, self.server)
				}
				.onAppear { DeepLink.setReady(true) }
				.onDisappear { DeepLink.setReady(false) }
				.onChange(of: PlayerEngine.shared.isExpanded) { _, newValue in
					self.isPlayerExpanded = newValue
				}
				.onChange(of: self.isPlayerExpanded) { _, newValue in
					PlayerEngine.shared.isExpanded = newValue
				}
			} else {
				OnboardingView(onboarding: $onboarding)
			}
		}
		// rebuilt on a theme or font change, so bars and every cached font are drawn again
		.id("\(ThemeManager.shared.current.rawValue)-\(FontPreferences.shared.useDyslexic)")
		.font(DTFont.base)
		// Hosted here, not on the tabs: `attemptLogin()` swaps the tabs for the launch spinner (and an account
		// switch tears them down), which dismissed a sheet opened in the first moments after launch.
		.sheet(isPresented: self.$isNavigatorSheetPresented) {
			Navigator.shared.sheet?.view
				.environment(\.server, self.server)
		}
		.onChange(of: Navigator.shared.sheet != nil) { _, hasSheet in
			self.isNavigatorSheetPresented = hasSheet
		}
		.onChange(of: self.isNavigatorSheetPresented) { _, isPresented in
			if !isPresented { Navigator.shared.sheet = nil }
		}
		.preferredColorScheme(ThemeManager.shared.preferredColorScheme)
		.toast(.app)
		.task {
			await self.attemptLogin()
		}
		.onOpenURL { url in
			DeepLink(url: url)?.open()
		}
		.onChange(of: self.scenePhase) { _, phase in
			switch phase {
				case .active:
					PushManager.shared.appDidBecomeActive()
					UnityEngine.shared.appDidBecomeActive()
				case .background:
					UnityEngine.shared.appDidEnterBackground()
				default:
					break
			}
		}
		.onChange(of: NetworkMonitor.shared.isOffline) { wasOffline, isOffline in
			// Came back online while stuck in offline mode (no `server` yet, saved accounts present) —
			// retry the handshake so the app transitions from offline-only library to the real session
			// without requiring a relaunch.
			guard wasOffline, !isOffline, self.server == nil, !self.auth.isEmpty else { return }
			Task {
				await self.attemptLogin()
			}
		}
		.onChange(of: self.onboarding) { _, newValue in
			guard newValue == .complete else { return }

			Task {
				await self.attemptLogin()
			}
		}
		.onChange(of: self.defaultAuthId) { _, newValue in
			// `LocalAccountsSettingsSection.activate(_:)` only flips `AuthInfo.defaultAuth` flags in
			// SwiftData — it doesn't know about `server`, so switching accounts there left the app
			// talking to the previously-active `NafynServer`/token until relaunch. Tearing `server`
			// down and re-running `attemptLogin()` here is what actually swaps the live connection.
			guard newValue != self.activeAuthId else { return }
			self.isLoading = true
			self.server = nil

			// Both are tied to the outgoing account's token/session; left running they'd keep
			// streaming/publishing against the server we're about to leave.
			AppSession.shared.deactivate()
			PlayerEngine.shared.stop()
			UnityEngine.shared.disconnect()
			PushManager.shared.signOut(server: nil)

			Task {
				await self.attemptLogin()
			}
		}
	}

	/// Zero-size, hidden `List`/`.swipeActions`/`.searchable` so UIKit builds and caches their backing
	/// classes (compositional-layout collection view, `UISearchController`, keyboard/predictive-text
	/// resources) during the launch spinner instead of on the user's first visit to Settings/Search —
	/// that first-ever construction is synchronous and multi-second, and was showing up as a dropped-
	/// framerate stall on first tap into either tab.
	private var warmup: some View {
		NavigationStack {
			List {
				Text(String())
					.swipeActions {
						Button(String()) {}
					}
			}
			.searchable(text: .constant(String()))
		}
		.frame(width: 0, height: 0)
		.opacity(0)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	@ContentBuilder
	private var tabs: some View {
		TabView(selection: Binding(get: { Navigator.shared.currentTab }, set: { Navigator.shared.currentTab = $0 })) {
			Tab(value: Navigator.Tabs.library) {
				LibraryView()
			} label: {
				Navigator.Tabs.library.view
			}

			Tab(value: Navigator.Tabs.requests) {
				RequestsView()
			} label: {
				Navigator.Tabs.requests.view
			}

			Tab(value: Navigator.Tabs.search, role: .search) {
				SearchView()
			} label: {
				Navigator.Tabs.search.view
			}
		}
		// Compact width keeps the floating tab bar; a regular-width window (iPhone Duo inner display, iPad
		// later) gets the sidebar-capable top bar instead of a bottom bar stretched across the display.
		.tabViewStyle(.sidebarAdaptable)
		.tabViewSearchActivation(.searchTabSelection)
		.tabViewBottomAccessory {
			MiniPlayerBar(namespace: self.playerZoomNamespace)
		}
	}

	private func tryLogin(auth: AuthInfo) async throws -> NafynServer? {
		try await AppSession.connect(auth: auth, context: self.modelContext)
	}

	private func attemptLogin() async {
		defer { self.isLoading = false }
		self.isLoading = true

		guard auth.count > 0 else { return }

		var s: NafynServer? = nil
		var activatedId: String? = nil
		let sort: [AuthInfo] = auth.sorted(by: { return $0.defaultAuth && !$1.defaultAuth })

		for a in sort {
			guard s == nil else { continue }

			if let serv: NafynServer = try? await self.tryLogin(auth: a) {
				s = serv
				activatedId = a.id
			}
		}

		self.server = s
		self.activeAuthId = activatedId

		if let s {
			AppSession.shared.activate(s)
		}
	}
}
