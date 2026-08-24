// Made by Lumaa

import SwiftUI
import Safyn

struct AccountsSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var isOpen = false
	@State private var isLoaded = false
	@State private var tokens: [RegisterTokenRow] = []
	@State private var toast = ToastState()

	var body: some View {
		Section(String(localized: "accounts")) {
			NavigationLink(value: Navigator.Paths.users) {
				Text("manage-users")
			}

			Toggle(String(localized: "open-registration"), isOn: Binding(get: { self.isOpen }, set: { self.setOpen($0) }))

			ForEach(self.tokens, id: \.id) { token in
				if let url = self.registerURL(for: token) {
					ShareLink(item: url) {
						Label(token.token, systemImage: "square.and.arrow.up")
							.font(.system(.footnote, design: .monospaced))
					}
				}
			}

			Button(String(localized: "create-invite-token")) {
				self.createToken()
			}
		}
		.task {
			guard !self.isLoaded, let server else { return }
			self.isLoaded = true
			if let response = try? await server.send(Settings.registrationOpen) as RegistrationOpenResponse {
				self.isOpen = response.open
			}
			if let rows = try? await server.send(Settings.registerTokens) as [RegisterTokenRow] {
				self.tokens = rows
			}
		}
		.toast(self.toast)
	}

	/// The register page's shareable URL for `token`, e.g. `https://server/register?token=...`, matching
	/// the web app's `/register?token=` invite flow.
	private func registerURL(for token: RegisterTokenRow) -> URL? {
		guard let server else { return nil }
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += "/register"
		components.queryItems = [URLQueryItem(name: "token", value: token.token)]
		return components.url
	}

	private func setOpen(_ open: Bool) {
		guard let server else { return }
		self.isOpen = open
		Task {
			do {
				_ = try await server.send(Settings.setRegistrationOpen(open: open)) as RegistrationOpenResponse
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func createToken() {
		guard let server else { return }
		Task {
			do {
				let token = try await server.send(Settings.createRegisterToken) as RegisterTokenRow
				self.tokens.insert(token, at: 0)
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
