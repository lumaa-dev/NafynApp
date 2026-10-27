// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct RootView: View {
	@Environment(\.scenePhase) private var scenePhase
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

	/// Mirrors `PlayerEngine.shared.isExpanded` as plain `@State`. The zoom transition's source
	/// geometry resolves against `MiniPlayerBar`'s `matchedTransitionSource` only when the presenting
	/// `isPresented` binding is backed by `@State` — driving `fullScreenCover` straight off an
	/// `@Observable` property (as before) makes the transition start from the screen center instead.
	@State private var isPlayerExpanded = false

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
				.sheet(isPresented: Binding(get: { Navigator.shared.sheet != nil }, set: { if !$0 { Navigator.shared.sheet = nil } })) {
					Navigator.shared.sheet?.view
						.environment(\.server, self.server)
				}
			} else {
				OnboardingView(onboarding: $onboarding)
			}
		}
		.id(ThemeManager.shared.current)
		.preferredColorScheme(ThemeManager.shared.preferredColorScheme)
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
		guard let url: URL = URL(string: auth.server) else { return nil }
		let inst: NafynInstance = try await NafynInstance.connect(appName: "Nafyn on iOS", to: url)
		let server: NafynServer = .init(instance: inst, authToken: auth.token)

		if Date.now > auth.tokenExpire {
			server.authToken = nil
			let res: AuthResponse = try await server.send(Auth.login(username: auth.username, password: auth.password))
			server.authToken = res.token
		}

		return (await self.getMe(server)) ? server : nil
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
			CoverArtLoader.shared.configure(server: s)
			PlayerEngine.shared.configure(server: s)
			PlayTracker.shared.configure(server: s)
			UnityEngine.shared.configure(server: s)
			DownloadManager.shared.configure(server: s)
			PushManager.shared.configure(server: s)
		}
	}

	private func getMe(_ server: NafynServer) async -> Bool {
		let user: NafynUser? = try? await server.send(User.me)
		return user != nil
	}
}
