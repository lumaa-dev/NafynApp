// Made by Lumaa

import Foundation
import UIKit
import UserNotifications
import Safyn

/// Owns everything push-related on the app side: the notification permission, the APNs device token, the
/// Live Activity / Now Playing push-to-start tokens, and registering all of them with the server.
///
/// Tokens are only ever held in memory and sent to the server — never logged or written to disk. A
/// registration that fails stays queued and is retried shortly after, on the next foreground and on the
/// next launch (the server upserts, so re-sending is always safe).
@Observable
final class PushManager: NSObject {
	static let shared = PushManager()

	private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

	/// Whether the OS will actually show our notifications (as opposed to never asked / denied).
	var isDenied: Bool { self.authorizationStatus == .denied }

	private weak var server: NafynServer?

	/// `false` between sign-out and the next sign-in: nothing is registered while logged out.
	private var isActive = false

	/// Latest token per kind, kept so a sign-in after a sign-out can re-register without waiting for the
	/// system to hand out a new one.
	private var latest: [AppleDeviceKind: String] = [:]
	private var pendingDevices: Set<AppleDeviceKind> = []
	private var pendingActivities: [PendingActivity] = []
	private var retryTask: Task<Void, Never>?

	private struct PendingActivity: Hashable {
		let kind: ActivityKind
		let refId: String
		let token: String
	}

	private static var environment: APNsEnvironment {
		#if DEBUG
		.sandbox
		#else
		.production
		#endif
	}

	private override init() {
		super.init()
	}

	// MARK: - Lifecycle

	/// Call once at launch, before the app finishes launching, so a notification tap that cold-starts the
	/// app is delivered to the delegate.
	func installDelegate() {
		let center = UNUserNotificationCenter.current()
		center.delegate = self
		center.setNotificationCategories([
			UNNotificationCategory(identifier: "NAFYN_REQUEST", actions: [], intentIdentifiers: [], options: []),
			UNNotificationCategory(identifier: "NAFYN_RELEASE", actions: [], intentIdentifiers: [], options: []),
		])
	}

	/// Call after every successful login.
	func configure(server: NafynServer) {
		self.server = server
		self.isActive = true

		if let base = URL(string: server.instance.baseURL.absoluteString), let token = server.authToken {
			SharedSession.save(SharedSession(baseURL: base, token: token))
		}

		// the token itself is available without notification permission, so this isn't gated on it
		UIApplication.shared.registerForRemoteNotifications()
		LiveActivityCoordinator.shared.start()
		RemoteMediaCoordinator.shared.start()

		self.pendingDevices.formUnion(self.latest.keys)
		Task {
			await self.refreshAuthorizationStatus()
			await self.flush()
		}
	}

	/// Signs this login out of push: asks the server to drop this login's tokens (`POST /auth/logout`) and
	/// stops registering until the next `configure(server:)`.
	func signOut(server: NafynServer?) {
		self.isActive = false
		self.server = nil
		self.pendingDevices.removeAll()
		self.pendingActivities.removeAll()
		self.retryTask?.cancel()
		SharedSession.clear()

		guard let server else { return }
		Task {
			_ = try? await server.sendRaw(Auth.logout)
		}
	}

	/// Retries anything that failed earlier. Call when the app becomes active.
	func appDidBecomeActive() {
		guard self.isActive else { return }
		Task {
			await self.refreshAuthorizationStatus()
			await self.flush()
		}
	}

	// MARK: - Permission

	func refreshAuthorizationStatus() async {
		self.authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
	}

	/// Asks for notification permission the first time it's needed (opening Notifications settings, first
	/// "Notify me", first request) — never cold at launch. Returns whether notifications are allowed.
	@discardableResult
	func requestAuthorizationIfNeeded() async -> Bool {
		await self.refreshAuthorizationStatus()
		if self.authorizationStatus == .notDetermined {
			_ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
			await self.refreshAuthorizationStatus()
		}
		if self.isActive {
			UIApplication.shared.registerForRemoteNotifications()
		}
		return self.authorizationStatus == .authorized || self.authorizationStatus == .provisional
	}

	// MARK: - Tokens

	func didRegister(deviceToken: Data) {
		self.submit(token: deviceToken, kind: .alert)
	}

	/// Queues `token` for `kind` and sends it right away if signed in.
	func submit(token: Data, kind: AppleDeviceKind) {
		self.latest[kind] = token.hexString
		guard self.isActive else { return }
		self.pendingDevices.insert(kind)
		Task { await self.flush() }
	}

	/// Registers the update token of a running Live Activity / Now Playing session. A 404 means it isn't
	/// the caller's or it's already over, which is ignored.
	func registerActivity(kind: ActivityKind, refId: String, token: Data) {
		guard self.isActive else { return }
		self.pendingActivities.append(PendingActivity(kind: kind, refId: refId, token: token.hexString))
		Task { await self.flush() }
	}

	private func flush() async {
		guard self.isActive, let server else { return }
		var failed = false

		for kind in self.pendingDevices {
			guard let token = self.latest[kind] else {
				self.pendingDevices.remove(kind)
				continue
			}
			do {
				_ = try await server.send(User.registerDevice(token: token, kind: kind, environment: Self.environment, deviceName: .value(UIDevice.current.name))) as AppleDevice
				self.pendingDevices.remove(kind)
			} catch {
				failed = true
			}
		}

		for activity in self.pendingActivities {
			do {
				_ = try await server.sendRaw(User.registerActivityToken(kind: activity.kind, refId: activity.refId, token: activity.token, environment: Self.environment))
				self.pendingActivities.removeAll(where: { $0 == activity })
			} catch NafynError.server(let statusCode, _) where statusCode == 404 {
				self.pendingActivities.removeAll(where: { $0 == activity })
			} catch {
				failed = true
			}
		}

		if failed {
			self.scheduleRetry()
		}
	}

	private func scheduleRetry() {
		guard self.retryTask == nil else { return }
		self.retryTask = Task {
			try? await Task.sleep(for: .seconds(30))
			self.retryTask = nil
			guard !Task.isCancelled else { return }
			await self.flush()
		}
	}
}

// MARK: - UNUserNotificationCenterDelegate

extension PushManager: UNUserNotificationCenterDelegate {
	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
		let userInfo = notification.request.content.userInfo
		return await MainActor.run {
			// already looking at what the notification is about: don't interrupt
			if let link = DeepLink(userInfo: userInfo), link.isCurrentlyVisible {
				return []
			}
			return [.banner, .list, .sound]
		}
	}

	nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
		let userInfo = response.notification.request.content.userInfo
		await MainActor.run {
			DeepLink(userInfo: userInfo)?.open()
		}
	}
}

extension Data {
	/// Lowercase hex, the form the server expects for APNs tokens.
	var hexString: String {
		self.map { String(format: "%02x", $0) }.joined()
	}
}
