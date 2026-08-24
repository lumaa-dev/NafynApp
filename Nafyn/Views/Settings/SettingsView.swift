// Made by Lumaa

import SwiftUI
import Safyn

struct SettingsView: View {
	@Environment(\.server) private var server: NafynServer?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(User.me) as NafynUser
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
			ProfileSettingsSection(user: self.user) { updated in
				self.user = updated
			}

			if self.user.permissions.has(.manageAccounts) {
				AccountsSettingsSection()
			}

			if self.user.permissions.has(.manageMusic) {
				StorageSettingsSection()
			}

			ApiTokensSettingsSection()
		}
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
	}
}
