// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct RootView: View {
	@Query private var auth: [AuthInfo]

	@State private var isLoading: Bool = false
	@State private var server: NafynServer? = nil

	@State private var onboarding: OnboardingView.OnboardingSteps = .welcome
	@Namespace private var playerZoomNamespace

	var body: some View {
		ZStack {
			DTColor.background.ignoresSafeArea()

			if isLoading {
				ProgressView()
					.progressViewStyle(.circular)
			} else if let server {
				self.tabs
				.environment(\.server, server)
				.environment(\.zoomNamespace, self.playerZoomNamespace)
				.fullScreenCover(isPresented: Binding(get: { PlayerEngine.shared.isExpanded }, set: { PlayerEngine.shared.isExpanded = $0 })) {
					NowPlayingView()
						.environment(\.server, server)
						.environment(\.zoomNamespace, self.playerZoomNamespace)
				}
				.sheet(isPresented: Binding(get: { Navigator.shared.sheet != nil }, set: { if !$0 { Navigator.shared.sheet = nil } })) {
					Navigator.shared.sheet?.view
						.environment(\.server, server)
				}
				.onAppear {
					PlayerEngine.shared.configure(server: server)
				}
			} else {
				OnboardingView(onboarding: $onboarding)
			}
		}
		.preferredColorScheme(ColorScheme.dark)
		.task {
			await self.attemptLogin()
		}
		.onChange(of: self.onboarding) { _, newValue in
			guard newValue == .complete else { return }

			Task {
				await self.attemptLogin()
			}
		}
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
		.tabViewBottomAccessory(isEnabled: PlayerEngine.shared.currentTrack != nil) {
			MiniPlayerBar()
		}
	}

	private func tryLogin(auth: AuthInfo) async throws -> NafynServer? {
		guard let url: URL = URL(string: auth.server) else { return nil }
		let inst: NafynInstance = try await NafynInstance.connect(to: url)
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

		guard auth.count > 0 && self.server == nil else { return }

		var s: NafynServer? = nil
		let sort: [AuthInfo] = auth.sorted(by: { return $0.defaultAuth && !$1.defaultAuth })

		for a in sort {
			guard s == nil else { continue }

			if let serv: NafynServer = try? await self.tryLogin(auth: a) {
				s = serv
			}
		}

		self.server = s
	}

	private func getMe(_ server: NafynServer) async -> Bool {
		let user: NafynUser? = try? await server.send(User.me)
		return user != nil
	}
}
