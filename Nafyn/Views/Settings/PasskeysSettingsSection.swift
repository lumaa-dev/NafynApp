// Made by Lumaa

import SwiftUI
import Safyn

struct PasskeysSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var passkeys: [PasskeySummary] = []
	@State private var isLoaded = false
	@State private var isRegistering = false
	@State private var showingLabelPrompt = false
	@State private var newLabel = ""
	@State private var toast = ToastState()

	var body: some View {
		Section {
			ForEach(self.passkeys) { passkey in
				VStack(alignment: .leading, spacing: 2) {
					Text(passkey.label ?? String(localized: "unnamed-passkey"))
						.foregroundStyle(DTColor.textPrimary)
					Text(passkey.createdAtDate, style: .date)
						.font(.footnote)
						.foregroundStyle(DTColor.textPrimary.opacity(0.55))
				}
				.swipeActions {
					Button(role: .destructive) {
						self.delete(passkey)
					} label: {
						Label(String(localized: "delete"), systemImage: "trash")
					}
					.tint(DTColor.buttonDanger)
					.disabled(NetworkMonitor.shared.isOffline)
				}
			}

			Button {
				self.showingLabelPrompt = true
			} label: {
				if self.isRegistering {
					ProgressView()
						.tint(DTColor.textPrimary)
				} else {
					Label(String(localized: "add-passkey"), systemImage: "person.badge.key")
				}
			}
			.disabled(self.isRegistering || NetworkMonitor.shared.isOffline)
		}
		header: {
			Text(String(localized: "passkeys"))
		} footer: {
			Text(String(localized: "passkeys-footer"))
		}
		.task {
			guard !self.isLoaded, let server else { return }
			self.isLoaded = true
			self.passkeys = (try? await server.send(User.passkeys)) ?? []
		}
		.alert(String(localized: "add-passkey"), isPresented: self.$showingLabelPrompt) {
			TextField(String(localized: "passkey-label"), text: self.$newLabel)
			Button(String(localized: "cancel"), role: .cancel) {
				self.newLabel = ""
			}
			Button(String(localized: "add")) {
				self.register()
			}
		} message: {
			Text(String(localized: "passkey-label-footer"))
		}
		.toast(self.toast)
	}

	private func register() {
		guard let server else { return }
		let label = self.newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
		self.newLabel = ""

		Task {
			self.isRegistering = true
			defer { self.isRegistering = false }

			do {
				try await PasskeyAuth.register(server: server, label: label.isEmpty ? nil : label)
				self.passkeys = (try? await server.send(User.passkeys)) ?? self.passkeys
				self.toast.success(String(localized: "passkey-added"))
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func delete(_ passkey: PasskeySummary) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.sendRaw(User.deletePasskey(id: passkey.id))
				self.passkeys.removeAll(where: { $0.id == passkey.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
