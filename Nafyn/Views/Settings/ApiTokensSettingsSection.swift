// Made by Lumaa

import SwiftUI
import Safyn

struct ApiTokensSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var tokens: [ApiTokenSummary] = []
	@State private var isLoaded = false
	@State private var newTokenValue: String? = nil
	@State private var toast = ToastState()

	var body: some View {
		Section(String(localized: "api-tokens")) {
			ForEach(self.tokens, id: \.id) { token in
				Text(token.name ?? String(localized: "unnamed-token"))
					.swipeActions {
						Button(role: .destructive) {
							self.delete(token)
						} label: {
							Label(String(localized: "delete"), systemImage: "trash")
						}
						.tint(DTColor.buttonDanger)
						.disabled(NetworkMonitor.shared.isOffline)
					}
			}

			if let newTokenValue {
				Text(newTokenValue)
					.font(.system(.footnote, design: .monospaced))
					.textSelection(.enabled)
			}

			Button(String(localized: "create-api-token")) {
				self.create()
			}
			.disabled(NetworkMonitor.shared.isOffline)
		}
		.task {
			guard !self.isLoaded, let server else { return }
			self.isLoaded = true
			self.tokens = (try? await server.send(User.apiTokens)) ?? []
		}
		.toast(self.toast)
	}

	private func create() {
		guard let server else { return }
		Task {
			do {
				let response = try await server.send(User.createApiToken(name: nil)) as CreateApiTokenResponse
				self.newTokenValue = response.token
				self.tokens.insert(ApiTokenSummary(id: response.id, userId: response.userId, name: response.name, createdAt: response.createdAt, lastUsedAt: response.lastUsedAt), at: 0)
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func delete(_ token: ApiTokenSummary) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.sendRaw(User.deleteApiToken(id: token.id))
				self.tokens.removeAll(where: { $0.id == token.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
