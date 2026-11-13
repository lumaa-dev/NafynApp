// Made by Lumaa

import SwiftUI
import AuthenticationServices
import Safyn

/// Last.fm scrobbling: the server scrobbles what every client plays once an account is connected. Connecting goes
/// through last.fm's own page in an `ASWebAuthenticationSession`, which the server sends back to `nafyn://lastfm`.
struct LastfmSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.webAuthenticationSession) private var webAuthenticationSession

	@State private var connection: LastfmConnection?
	@State private var isBusy = false
	@State private var toast = ToastState()

	var body: some View {
		Group {
			Section {
				if let connection {
					if !connection.available {
						Text("lastfm-unavailable")
							.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					} else if let username = connection.username {
						LabeledContent(String(localized: "lastfm-account"), value: username)

						Toggle(String(localized: "lastfm-scrobbling"), isOn: Binding(
							get: { connection.scrobbling },
							set: { self.setScrobbling($0) }
						))
						.tint(DTColor.statusSuccess)
						.disabled(self.isBusy || NetworkMonitor.shared.isOffline)
					} else {
						Button {
							self.connect()
						} label: {
							Label(String(localized: "lastfm-connect"), systemImage: "link")
								.foregroundStyle(Color.primary)
						}
						.tint(Color.primary)
						.disabled(self.isBusy || NetworkMonitor.shared.isOffline)
					}
				} else {
					ProgressView()
						.tint(DTColor.textPrimary)
				}
			} footer: {
				Text("lastfm-footer")
			}

			if connection?.username != nil {
				Section {
					Button(role: .destructive) {
						self.disconnect()
					} label: {
						Text("lastfm-disconnect")
					}
					.tint(DTColor.dangerText)
					.disabled(self.isBusy || NetworkMonitor.shared.isOffline)
				}
			}
		}
		.task { await self.load() }
		.toast(self.toast)
	}

	private func load() async {
		guard let server else { return }
		do {
			self.connection = try await server.send(User.lastfm)
		} catch {
			self.toast.failure(error)
		}
	}

	private func connect() {
		guard let server, !self.isBusy else { return }
		self.isBusy = true
		Task {
			defer { self.isBusy = false }
			do {
				let link: LastfmConnectResponse = try await server.send(User.connectLastfm(client: .app))
				let callback = try await self.webAuthenticationSession.authenticate(using: link.url, callbackURLScheme: "nafyn", preferredBrowserSession: .ephemeral)
				let status = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "status" }?.value
				await self.load()
				if status == "connected" {
					PlayTracker.shared.setScrobbling(self.connection?.scrobbling ?? true)
					self.toast.success(String(localized: "lastfm-connected"))
				} else {
					self.toast.failure(NafynError.decoding(String(localized: "lastfm-connect-failed")))
				}
			} catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
				// closed by the person: nothing to say
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
				self.connection = try await server.send(User.updateLastfm(scrobbling: scrobbling))
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
				let _: RemovedResponse = try await server.send(User.disconnectLastfm)
				PlayTracker.shared.setScrobbling(false)
				await self.load()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
