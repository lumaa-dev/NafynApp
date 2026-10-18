// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn

struct LocalAccountsSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
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

		// removing the account in use signs it out server-side too, which drops this login's push tokens
		if wasDefault {
			PushManager.shared.signOut(server: self.server)
		}
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
					Button {
						self.dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "cancel"))
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
							Image(systemName: "checkmark")
						}
					}
					.accessibilityLabel(String(localized: "save"))
					.disabled(!self.canSubmit)
					.tint(Color.accentColor)
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
				let instance = try await NafynInstance.connect(appName: "Nafyn on iOS", to: normalizedServerURL)
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
