// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct SettingsView: View {
	@Environment(\.server) private var server: NafynServer?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(User.me) as NafynUser
		} skeleton: {
			AnyView(SkeletonFormRows())
		} content: { user, _ in
			SettingsForm(initialUser: user)
		}
		.navigationTitle(String(localized: "settings"))
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
				NavigationLink {
					SettingsSectionScreen(title: String(localized: "accounts")) {
						AccountsSettingsSection()
					}
				} label: {
					Label(String(localized: "accounts"), systemImage: "person.2")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			if self.user.permissions.has(.manageMusic) {
				NavigationLink {
					SettingsSectionScreen(title: String(localized: "storage")) {
						StorageSettingsSection()
					}
				} label: {
					Label(String(localized: "storage"), systemImage: "internaldrive")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			}

			AppearanceSettingsSection()

			InsightsSettingsSection()

			AppleMusicImportSection()

			ApiTokensSettingsSection()
		}
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
	}
}

private struct AppearanceSettingsSection: View {
	@AppStorage(LyricsPanel.useSystemFontKey) private var lyricsUseSystemFont = false

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
		}
		header: {
			Text(String(localized: "appearance"))
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(String(localized: "appearance-theme-footer"))
				Text(String(localized: "appearance-lyrics-font-footer"))
			}
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
	@State private var errorMessage: String? = nil

	private var canSubmit: Bool {
		!self.serverURL.isEmpty && !self.username.isEmpty && !self.password.isEmpty && !self.isSaving
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
				let instance = try await NafynInstance.connect(to: normalizedServerURL)
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

/// Hosts one of the major settings sections (profile/accounts/storage) as its own pushed screen, since
/// each is a `Section`-returning view meant to live inside a `Form`.
private struct SettingsSectionScreen<Content: View>: View {
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
