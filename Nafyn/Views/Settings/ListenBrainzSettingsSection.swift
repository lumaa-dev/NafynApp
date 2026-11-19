// Made by Lumaa

import SwiftUI
import Safyn

/// ListenBrainz scrobbling: the server scrobbles what every client plays once an account is connected. Connecting
/// takes the user token from the ListenBrainz settings page, which the server checks with ListenBrainz before
/// keeping it.
struct ListenBrainzSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var connection: ListenBrainzConnection?
	@State private var token = ""
	@State private var isBusy = false
	@State private var toast = ToastState()

	private static let settingsURL = URL(string: "https://listenbrainz.org/settings/")!

	var body: some View {
		Group {
			Section {
				if let connection {
					if let username = connection.username {
						LabeledContent(String(localized: "listenbrainz-account"), value: username)

						Toggle(String(localized: "listenbrainz-scrobbling"), isOn: Binding(
							get: { connection.scrobbling },
							set: { self.setScrobbling($0) }
						))
						.tint(DTColor.statusSuccess)
						.disabled(self.isBusy || NetworkMonitor.shared.isOffline)
					} else {
						SecureField(String(localized: "listenbrainz-token"), text: self.$token)
							.textContentType(.password)
							.autocorrectionDisabled()
							.textInputAutocapitalization(.never)
							.submitLabel(.go)
							.onSubmit { self.connect() }

						Button {
							Navigator.shared.sheet = Navigator.Paths.web(url: Self.settingsURL)
						} label: {
							Label(String(localized: "listenbrainz-get-token"), systemImage: "key")
								.foregroundStyle(Color.primary)
						}
						.tint(Color.primary)

						Button {
							self.connect()
						} label: {
							Label(String(localized: "listenbrainz-connect"), systemImage: "link")
								.foregroundStyle(Color.primary)
						}
						.tint(Color.primary)
						.disabled(self.isBusy || NetworkMonitor.shared.isOffline || self.trimmedToken.isEmpty)
					}
				} else {
					ProgressView()
						.tint(DTColor.textPrimary)
				}
			} footer: {
				Text("listenbrainz-footer")
			}

			if connection?.username != nil {
				Section {
					Button(role: .destructive) {
						self.disconnect()
					} label: {
						Text("listenbrainz-disconnect")
					}
					.tint(DTColor.dangerText)
					.disabled(self.isBusy || NetworkMonitor.shared.isOffline)
				}
			}
		}
		.task { await self.load() }
		.toast(self.toast)
	}

	private var trimmedToken: String {
		self.token.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func load() async {
		guard let server else { return }
		do {
			self.connection = try await server.send(User.listenBrainz)
		} catch {
			self.toast.failure(error)
		}
	}

	private func connect() {
		let token = self.trimmedToken
		guard let server, !self.isBusy, !token.isEmpty else { return }
		self.isBusy = true
		Task {
			defer { self.isBusy = false }
			do {
				let connection: ListenBrainzConnection = try await server.send(User.connectListenBrainz(token: token))
				self.connection = connection
				self.token = ""
				PlayTracker.shared.setScrobbling(connection.scrobbling)
				self.toast.success(String(localized: "listenbrainz-connected"))
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func setScrobbling(_ scrobbling: Bool) {
		guard let server else { return }
		self.isBusy = true
		Task {
			defer { self.isBusy = false }
			do {
				self.connection = try await server.send(User.updateListenBrainz(scrobbling: scrobbling))
				PlayTracker.shared.setScrobbling(self.connection?.scrobbling ?? false)
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func disconnect() {
		guard let server else { return }
		self.isBusy = true
		Task {
			defer { self.isBusy = false }
			do {
				let _: RemovedResponse = try await server.send(User.disconnectListenBrainz)
				PlayTracker.shared.setScrobbling(false)
				await self.load()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
