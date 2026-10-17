// Made by Lumaa

import SwiftUI
import Safyn

/// Settings → Notifications: the user's webhooks, their registered Apple devices and the releases they
/// follow. Mirrors the web app's notifications settings.
struct NotificationsSettingsSection: View {
	var body: some View {
		Group {
			NotificationPermissionBanner()
			WebhooksSettingsSection(scope: .personal)
			AppleDevicesSection()
			FollowedReleasesSection()
		}
		.task {
			// the first moment notifications are clearly relevant to the user
			await PushManager.shared.requestAuthorizationIfNeeded()
		}
	}
}

/// Shown when the OS permission was denied: the rest of the app keeps working, but nothing will be shown.
private struct NotificationPermissionBanner: View {
	var body: some View {
		if PushManager.shared.isDenied {
			Section {
				VStack(alignment: .leading, spacing: 10) {
					Label(String(localized: "notifications-disabled"), systemImage: "bell.slash")
						.foregroundStyle(DTColor.textPrimary)

					Text("notifications-disabled-detail")
						.font(.footnote)
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))

					Button(String(localized: "open-settings")) {
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					}
					.buttonStyle(.borderless)
				}
				.padding(.vertical, 4)
			}
		}
	}
}

private struct AppleDevicesSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var devices: [AppleDevice] = []
	@State private var isLoaded = false
	@State private var toast = ToastState()

	var body: some View {
		Section {
			ForEach(self.devices) { device in
				self.row(device)
			}

			if self.isLoaded && self.devices.isEmpty {
				Text("apple-devices-empty")
					.foregroundStyle(DTColor.textPrimary.opacity(0.55))
			}
		} header: {
			Text(String(localized: "apple-devices"))
		}
		.task {
			guard let server, !self.isLoaded else { return }
			do {
				self.devices = try await server.send(User.devices)
			} catch {
				self.toast.failure(error)
			}
			self.isLoaded = true
		}
		.toast(self.toast)
	}

	@ViewBuilder
	private func row(_ device: AppleDevice) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				Text(device.deviceName ?? Self.kindLabel(device.kind))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)

				if device.currentSession {
					Text("this-device")
						.font(DTFont.system(12, weight: .semibold))
						.padding(.horizontal, 7)
						.padding(.vertical, 2)
						.background(DTColor.statusSuccess, in: Capsule())
						.foregroundStyle(Color.black.opacity(0.8))
				}

				if device.environment == .sandbox {
					Text("development-build")
						.font(DTFont.system(12, weight: .semibold))
						.padding(.horizontal, 7)
						.padding(.vertical, 2)
						.overlay(Capsule().strokeBorder(DTColor.textPrimary.opacity(0.4), lineWidth: 1))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
				}
			}

			Text(Self.kindLabel(device.kind))
				.font(.footnote)
				.foregroundStyle(DTColor.textPrimary.opacity(0.55))

			Text("device-last-seen \(device.lastSeenAtDate.formatted(.relative(presentation: .named)))")
				.font(.footnote)
				.foregroundStyle(DTColor.textPrimary.opacity(0.55))
		}
		.padding(.vertical, 2)
		.swipeActions {
			Button(role: .destructive) {
				self.remove(device)
			} label: {
				Label(String(localized: "remove"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
		}
	}

	static func kindLabel(_ kind: AppleDeviceKind) -> String {
		switch kind {
			case .alert: String(localized: "device-kind-alert")
			case .laStartRequest: String(localized: "device-kind-la-request")
			case .laStartRelease: String(localized: "device-kind-la-release")
			case .nowPlayingStart: String(localized: "device-kind-now-playing")
		}
	}

	private func remove(_ device: AppleDevice) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.sendRaw(User.deleteDevice(id: device.id))
				self.devices.removeAll(where: { $0.id == device.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

private struct FollowedReleasesSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var subscriptions: [ReleaseSubscription] = []
	@State private var isLoaded = false
	@State private var toast = ToastState()

	var body: some View {
		Section {
			ForEach(self.subscriptions) { subscription in
				self.row(subscription)
			}

			if self.isLoaded && self.subscriptions.isEmpty {
				Text("followed-releases-empty")
					.foregroundStyle(DTColor.textPrimary.opacity(0.55))
			}
		} header: {
			Text(String(localized: "followed-releases"))
		}
		.task {
			guard let server, !self.isLoaded else { return }
			do {
				let page: PaginatedResponse<ReleaseSubscription> = try await server.fetchPaginated(path: "/api/v1/subscriptions", page: 1, limit: 100)
				self.subscriptions = page.items
			} catch {
				self.toast.failure(error)
			}
			self.isLoaded = true
		}
		.toast(self.toast)
	}

	@ViewBuilder
	private func row(_ subscription: ReleaseSubscription) -> some View {
		let destination: Navigator.Paths = subscription.type == .album ? .album(id: subscription.musicbrainzId) : .track(id: subscription.musicbrainzId)

		HStack(alignment: .center, spacing: 12) {
			NavigationLink(value: destination) {
				VStack(alignment: .leading, spacing: 2) {
					Text(subscription.title ?? subscription.musicbrainzId)
						.foregroundStyle(DTColor.textPrimary)
						.lineLimit(1)

					if let artist = subscription.artistName {
						Text(artist)
							.font(.footnote)
							.foregroundStyle(DTColor.textPrimary.opacity(0.55))
							.lineLimit(1)
					}

					if subscription.notifiedAt != nil {
						Text("out-now")
							.font(DTFont.system(12))
							.foregroundStyle(DTColor.statusSuccess)
					} else if let day = subscription.releaseDay {
						ReleaseCountdown(releaseDate: day, compact: true)
					}
				}
			}
			.tint(Color.primary)

			if subscription.notifiedAt == nil {
				Button(String(localized: "unfollow")) {
					self.unfollow(subscription)
				}
				.buttonStyle(.borderless)
				.font(.subheadline)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
	}

	private func unfollow(_ subscription: ReleaseSubscription) {
		guard let server else { return }
		Task {
			do {
				try await server.setFollowing(false, mbid: subscription.musicbrainzId, type: subscription.type)
				self.subscriptions.removeAll(where: { $0.id == subscription.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
