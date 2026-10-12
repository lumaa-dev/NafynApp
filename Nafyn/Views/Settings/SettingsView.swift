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

			AppearanceSettingsSection(canManageFileSize: self.user.permissions.has(.manageMusic))

			Section {
				NavigationLink(value: Navigator.Paths.settingsDownloads) {
					Label(String(localized: "downloads"), systemImage: "arrow.down.circle")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			Section {
				NavigationLink(value: Navigator.Paths.settingsPrivacy) {
					Label(String(localized: "privacy"), systemImage: "lock.shield")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			InsightsSettingsSection()

			UnitySettingsSection()

			AppleMusicImportSection()

			ApiTokensSettingsSection()
		}
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
	}
}

private struct AppearanceSettingsSection: View {
	let canManageFileSize: Bool

	@Environment(\.server) private var server: NafynServer?
	@AppStorage(LyricsPanel.useSystemFontKey) private var lyricsUseSystemFont = false

	@State private var showDuration = DisplayPreferences.shared.showDuration
	@State private var showFileSize = DisplayPreferences.shared.showFileSize

	private var themeBinding: Binding<AppTheme> {
		Binding(
			get: { ThemeManager.shared.current },
			set: { ThemeManager.shared.current = $0 }
		)
	}

	var body: some View {
		Section {
			Picker(String(localized: "theme"), selection: self.themeBinding) {
				ForEach(AppTheme.allCases) { theme in
					Label(theme.label, systemImage: theme.symbolName)
						.tag(theme)
				}
			}

			Toggle(String(localized: "lyrics-system-font"), isOn: self.$lyricsUseSystemFont)

			Toggle(String(localized: "show-duration"), isOn: self.$showDuration)
				.onChange(of: self.showDuration) { _, newValue in
					DisplayPreferences.shared.showDuration = newValue
					self.pushUpdate(showDuration: newValue)
				}

			if self.canManageFileSize {
				Toggle(String(localized: "show-file-size"), isOn: self.$showFileSize)
					.onChange(of: self.showFileSize) { _, newValue in
						DisplayPreferences.shared.showFileSize = newValue
						self.pushUpdate(showFileSize: newValue)
					}
			}
		}
		header: {
			Text(String(localized: "appearance"))
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(String(localized: "appearance-theme-footer"))
				Text(String(localized: "appearance-lyrics-font-footer"))
				Text(String(localized: "appearance-duration-footer"))
				if self.canManageFileSize {
					Text(String(localized: "appearance-file-size-footer"))
				}
			}
		}
		.task {
			await self.refreshFromServer()
		}
	}

	private func refreshFromServer() async {
		guard let server else { return }
		guard let settings = try? await server.send(User.appearanceSettings) as AppearanceSettings else { return }
		DisplayPreferences.shared.apply(settings)
		self.showDuration = settings.showDuration
		self.showFileSize = settings.showFileSize
	}

	private func pushUpdate(showFileSize: Bool? = nil, showDuration: Bool? = nil) {
		guard let server else { return }
		Task {
			_ = try? await server.send(User.updateAppearanceSettings(showFileSize: showFileSize, showDuration: showDuration)) as AppearanceSettings
		}
	}
}

private struct LocalAccountsSettingsSection: View {
	@Environment(\.modelContext) private var modelContext: ModelContext
	@Query private var auths: [AuthInfo]

	@State private var showingAddAccount = false

	private var sortedAuths: [AuthInfo] {
		self.auths.sorted { lhs, rhs in
			if lhs.defaultAuth != rhs.defaultAuth {
				return lhs.defaultAuth && !rhs.defaultAuth
			}
			if lhs.server != rhs.server {
				return lhs.server.localizedCaseInsensitiveCompare(rhs.server) == .orderedAscending
			}
			return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
		}
	}

	var body: some View {
		Section {
			ForEach(self.sortedAuths) { auth in
				HStack(spacing: 12) {
					Image(systemName: auth.defaultAuth ? "checkmark.circle.fill" : "person.crop.circle")
						.imageScale(.large)
						.foregroundStyle(auth.defaultAuth ? DTColor.statusSuccess : DTColor.textPrimary.opacity(0.35))

					VStack(alignment: .leading, spacing: 2) {
						Text(auth.username)
							.foregroundStyle(DTColor.textPrimary)
						Text(auth.server)
							.font(.footnote)
							.foregroundStyle(DTColor.textPrimary.opacity(0.55))
							.lineLimit(1)
					}

					Spacer()

					if !auth.defaultAuth {
						Button(String(localized: "switch")) {
							self.activate(auth)
						}
						.buttonStyle(.borderless)
					}
				}
				.swipeActions {
					Button(role: .destructive) {
						self.delete(auth)
					} label: {
						Label(String(localized: "delete"), systemImage: "trash")
					}
					.tint(DTColor.buttonDanger)
				}
			}

			Button {
				self.showingAddAccount = true
			} label: {
				Label(String(localized: "add-account"), systemImage: "plus")
			}
		}
		header: {
			Text(String(localized: "app-accounts"))
		} footer: {
			Text(String(localized: "app-accounts-footer"))
		}
		.sheet(isPresented: self.$showingAddAccount) {
			AddLocalAccountSheet()
		}
	}

	private func activate(_ auth: AuthInfo) {
		for savedAuth in self.auths {
			savedAuth.defaultAuth = savedAuth.id == auth.id
		}
		try? self.modelContext.save()
	}

	private func delete(_ auth: AuthInfo) {
		let wasDefault = auth.defaultAuth
		self.modelContext.delete(auth)

		if wasDefault, let nextAuth = self.auths.first(where: { $0.id != auth.id }) {
			nextAuth.defaultAuth = true
		}

		try? self.modelContext.save()
	}
}

private struct AddLocalAccountSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var modelContext: ModelContext
	@Query private var auths: [AuthInfo]

	@State private var serverURL = ""
	@State private var username = ""
	@State private var password = ""
	@State private var isSaving = false
	@State private var isPasskeyAuthenticating = false
	@State private var errorMessage: String? = nil

	private var canSubmit: Bool {
		!self.serverURL.isEmpty && !self.username.isEmpty && !self.password.isEmpty && !self.isSaving
	}

	private var canUsePasskey: Bool {
		!self.serverURL.isEmpty && !self.isSaving && !self.isPasskeyAuthenticating
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(String(localized: "server.url"), text: self.$serverURL)
						.textContentType(.URL)
						#if !os(macOS)
						.keyboardType(.URL)
						.textInputAutocapitalization(.never)
						#endif
						.autocorrectionDisabled()

					TextField(String(localized: "username"), text: self.$username)
						.textContentType(.username)
						#if !os(macOS)
						.keyboardType(.asciiCapable)
						.textInputAutocapitalization(.never)
						#endif
						.autocorrectionDisabled()

					SecureField(String(localized: "password"), text: self.$password)
						.textContentType(.password)
				}

				Section {
					Button {
						self.signInWithPasskey()
					} label: {
						if self.isPasskeyAuthenticating {
							ProgressView()
								.tint(DTColor.textPrimary)
						} else {
							Label(String(localized: "sign-in-with-passkey"), systemImage: "person.badge.key")
						}
					}
					.disabled(!self.canUsePasskey)
				}

				if let errorMessage {
					Section {
						Text(errorMessage)
							.foregroundStyle(DTColor.buttonDanger)
					}
				}
			}
			.scrollContentBackground(.hidden)
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "add-account"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "cancel")) {
						self.dismiss()
					}
					.tint(Color.primary)
				}

				ToolbarItem(placement: .confirmationAction) {
					Button {
						self.addAccount()
					} label: {
						if self.isSaving {
							ProgressView()
								.tint(DTColor.textPrimary)
						} else {
							Text(String(localized: "save"))
						}
					}
					.disabled(!self.canSubmit)
					.tint(Color.primary)
				}
			}
		}
	}

	private func addAccount() {
		Task {
			do {
				withAnimation {
					self.isSaving = true
					self.errorMessage = nil
				}

				let normalizedServerURL = try self.normalizedServerURL()
				let instance = try await NafynInstance.connect(appName: "Nafyn", to: normalizedServerURL)
				let server = NafynServer(instance: instance)
				let response: AuthResponse = try await server.send(Auth.login(username: self.username, password: self.password))

				for auth in self.auths {
					auth.defaultAuth = false
				}

				if let existingAuth = self.auths.first(where: { $0.server == normalizedServerURL.absoluteString && $0.username == self.username }) {
					existingAuth.password = self.password
					existingAuth.token = response.token
					existingAuth.tokenExpire = Date.now.addingTimeInterval(60 * 60 * 24 * 7)
					existingAuth.defaultAuth = true
				} else {
					let auth = AuthInfo(
						server: normalizedServerURL.absoluteString,
						username: self.username,
						password: self.password,
						token: response.token,
						tokenExpire: Date.now.addingTimeInterval(60 * 60 * 24 * 7),
						defaultAuth: true
					)
					self.modelContext.insert(auth)
				}

				try self.modelContext.save()
				self.dismiss()
			} catch {
				withAnimation {
					self.errorMessage = error.localizedDescription
					self.isSaving = false
				}
			}
		}
	}

	private func signInWithPasskey() {
		Task {
			withAnimation {
				self.isPasskeyAuthenticating = true
				self.errorMessage = nil
			}
			defer { withAnimation { self.isPasskeyAuthenticating = false } }

			do {
				let normalizedServerURL = try self.normalizedServerURL()
				let instance = try await NafynInstance.connect(appName: "Nafyn", to: normalizedServerURL)
				let response = try await PasskeyAuth.login(instance: instance)

				for auth in self.auths {
					auth.defaultAuth = false
				}

				// Passkey sign-in has no password to persist, so token refresh on expiry (`RootView`'s
				// `tryLogin`) can't silently re-authenticate this account — the user re-authenticates via
				// passkey or password once the 7-day token lapses, same as any revoked session.
				if let existingAuth = self.auths.first(where: { $0.server == normalizedServerURL.absoluteString && $0.username == response.user.username }) {
					existingAuth.token = response.token
					existingAuth.tokenExpire = Date.now.addingTimeInterval(60 * 60 * 24 * 7)
					existingAuth.defaultAuth = true
				} else {
					let auth = AuthInfo(
						server: normalizedServerURL.absoluteString,
						username: response.user.username,
						password: "",
						token: response.token,
						tokenExpire: Date.now.addingTimeInterval(60 * 60 * 24 * 7),
						defaultAuth: true
					)
					self.modelContext.insert(auth)
				}

				try self.modelContext.save()
				self.dismiss()
			} catch {
				withAnimation {
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}

	private func normalizedServerURL() throws -> URL {
		var urlString = self.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
		if !urlString.starts(with: "http://") && !urlString.starts(with: "https://") {
			urlString = "https://\(urlString)"
		}
		while urlString.hasSuffix("/") {
			urlString.removeLast()
		}

		guard let url = URL(string: urlString) else { throw NafynError.invalidURL }
		return url
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
