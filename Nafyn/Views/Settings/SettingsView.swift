// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct SettingsView: View {
	@Environment(\.server) private var server: NafynServer?
	@Query private var auths: [AuthInfo]

	/// The account settings should show, independent of whether `server` connected: the default saved
	/// account, or whichever one happens to be saved if none is marked default.
	private var activeAuth: AuthInfo? {
		self.auths.first(where: { $0.defaultAuth }) ?? self.auths.first
	}

	var body: some View {
		AsyncContentView {
			// Settings (crucially, `DownloadsSettingsSection` and the theme picker — entirely local, no
			// network of their own) shouldn't become unreachable just because the profile fetch can't
			// reach the server, e.g. offline/airplane mode — including the case where `RootView` never
			// got a live `server` at all because the device had no connectivity at launch. Falling back
			// to the last-known `NafynUser` (keyed by the saved account, not the live `server`, so it's
			// reachable even without one) lets the rest of the screen render from cache instead of a
			// hard error wall.
			if let server {
				do {
					let user: NafynUser = try await server.send(User.me)
					if let activeAuth {
						CachedUserStore.save(user, for: activeAuth)
					}
					return user
				} catch {
					if let activeAuth, let cached = CachedUserStore.load(for: activeAuth) {
						return cached
					}
					throw error
				}
			} else if let activeAuth, let cached = CachedUserStore.load(for: activeAuth) {
				return cached
			} else {
				throw NafynError.unauthenticated
			}
		} skeleton: {
			AnyView(SkeletonFormRows())
		} content: { user, _ in
			SettingsForm(initialUser: user)
		}
		.navigationTitle(String(localized: "settings"))
	}
}

/// Persists the last successfully-fetched `NafynUser` per account (keyed by the saved account's server
/// URL + username rather than the live `NafynServer`/token, so it's readable even when there's no
/// connected `server` at all — see `RootView`'s offline-library mode), purely so `SettingsView` can
/// still render offline.
private enum CachedUserStore {
	private static func key(for auth: AuthInfo) -> String {
		"nafyn.cachedUser.\(auth.server)|\(auth.username)"
	}

	static func save(_ user: NafynUser, for auth: AuthInfo) {
		guard let data = try? JSONEncoder().encode(user) else { return }
		UserDefaults.standard.set(data, forKey: self.key(for: auth))
	}

	static func load(for auth: AuthInfo) -> NafynUser? {
		guard let data = UserDefaults.standard.data(forKey: self.key(for: auth)) else { return nil }
		return try? JSONDecoder().decode(NafynUser.self, from: data)
	}
}

private struct SettingsForm: View {
	@State private var user: NafynUser

	init(initialUser: NafynUser) {
		self._user = State(initialValue: initialUser)
	}

	var body: some View {
		Form {
			LocalAccountsSettingsSection()

			NavigationLink {
				SettingsSectionScreen(title: String(localized: "profile")) {
					ProfileSettingsSection(user: self.user) { updated in
						self.user = updated
					}
				}
			} label: {
				Label(String(localized: "profile"), systemImage: "person.crop.circle")
					.foregroundStyle(Color.primary)
			}
			.tint(Color.primary)

			if self.user.permissions.has(.manageAccounts) {
				NavigationLink(value: Navigator.Paths.settingsAccounts) {
					Label(String(localized: "accounts"), systemImage: "person.2")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			if self.user.permissions.has(.manageMusic) {
				NavigationLink(value: Navigator.Paths.settingsStorage) {
					Label(String(localized: "storage"), systemImage: "internaldrive")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			Section {
				NavigationLink(value: Navigator.Paths.settingsAppearance) {
					Label(String(localized: "appearance"), systemImage: "paintpalette")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)

				NavigationLink(value: Navigator.Paths.settingsPrivacy) {
					Label(String(localized: "privacy"), systemImage: "lock.shield")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)

				NavigationLink(value: Navigator.Paths.settingsNotifications) {
					Label(String(localized: "notifications"), systemImage: "bell.badge")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)

				NavigationLink(value: Navigator.Paths.settingsInsights) {
					Label(String(localized: "insights"), systemImage: "chart.bar")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)

				NavigationLink(value: Navigator.Paths.settingsUnity) {
					Label {
						Text(String("Nafyn Unity"))
					} icon: {
						Image(.nafynUnity)
					}
					.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			if self.user.permissions.has(.manageWebhooks) {
				NavigationLink(value: Navigator.Paths.settingsWebhooks) {
					Label(String(localized: "webhooks"), systemImage: "point.3.connected.trianglepath.dotted")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			Section {
				NavigationLink(value: Navigator.Paths.settingsDownloads) {
					Label(String(localized: "downloads"), systemImage: "arrow.down.circle")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			AppleMusicImportSection()

			ApiTokensSettingsSection()
		}
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
	}
}

/// Hosts one of the major settings sections (accounts/storage, plus profile inline) as its own pushed
/// screen, since each is a `Section`-returning view meant to live inside a `Form`. Not `private` — the
/// accounts/storage cases are constructed from `Navigator.Paths.view` in `Navigator.swift`, since they
/// need to be typed pushes on the tab's own stack (see that file's `.settingsAccounts`/`.settingsStorage`).
struct SettingsSectionScreen<Content: View>: View {
	let title: String
	@ViewBuilder let content: () -> Content

	var body: some View {
		Form {
			self.content()
		}
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.navigationTitle(self.title)
		.navigationBarTitleDisplayMode(.inline)
	}
}
