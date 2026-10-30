// Made by Lumaa

import Foundation
import SwiftData
import Safyn

/// The signed-in `NafynServer`, reachable without a view.
///
/// `RootView` builds the server and hands it over through ``activate(_:)``. App Intents (Siri, Shortcuts,
/// Spotlight results) can run before any view exists, when the system launches the app in the background;
/// ``resolveServer()`` then signs in from the saved account exactly as `RootView` would.
@MainActor
final class AppSession {
	static let shared = AppSession()

	private(set) var server: NafynServer?

	/// ID of the signed-in user, once known.
	private(set) var userId: String?

	private var resolving: Task<NafynServer, Error>?

	private init() {}

	/// Makes `server` the app-wide session and points every engine at it.
	func activate(_ server: NafynServer) {
		self.server = server

		CoverArtLoader.shared.configure(server: server)
		PlayerEngine.shared.configure(server: server)
		PlayTracker.shared.configure(server: server)
		UnityEngine.shared.configure(server: server)
		DownloadManager.shared.configure(server: server)
		PushManager.shared.configure(server: server)

		Task {
			self.userId = (try? await server.send(User.me) as NafynUser)?.id
			SpotlightIndexer.shared.scheduleSync()
		}
	}

	func deactivate() {
		self.server = nil
		self.userId = nil
		SpotlightIndexer.shared.reset()
		Task { await LibraryCatalog.shared.invalidate() }
	}

	/// The live server, or one signed in from the default saved account.
	func resolveServer() async throws -> NafynServer {
		if let server = self.server { return server }
		if let resolving = self.resolving { return try await resolving.value }

		let task = Task { @MainActor () throws -> NafynServer in
			let context = ModelContext(NafynApp.container)
			let accounts = (try? context.fetch(FetchDescriptor<AuthInfo>())) ?? []

			for account in accounts.sorted(by: { $0.defaultAuth && !$1.defaultAuth }) {
				if let server = try? await Self.connect(auth: account, context: context) {
					self.activate(server)
					return server
				}
			}
			throw NafynError.unauthenticated
		}
		self.resolving = task
		defer { self.resolving = nil }
		return try await task.value
	}

	// MARK: - Signing in

	/// Reuses the saved session; a new one (`Auth.login`, which shows up as another "Nafyn on iOS" device
	/// in the user's sessions) is only created when the server rejects the saved token, or when there is
	/// none. A network failure never logs in: the token is still good, the server is just unreachable.
	static func connect(auth: AuthInfo, context: ModelContext) async throws -> NafynServer? {
		guard let url = URL(string: auth.server) else { return nil }
		let instance = try await NafynInstance.connect(appName: "Nafyn on iOS", to: url)
		let server = NafynServer(instance: instance, authToken: auth.token.isEmpty ? nil : auth.token)

		if server.authToken != nil {
			switch await Self.checkSession(server) {
				case .valid:
					return server
				case .unreachable:
					return nil
				case .rejected:
					break
			}
		}

		server.authToken = nil
		let response: AuthResponse = try await server.send(Auth.login(username: auth.username, password: auth.password))
		server.authToken = response.token

		// persist the fresh session, otherwise every launch would log in again
		auth.token = response.token
		auth.tokenExpire = Date.now.addingTimeInterval(60 * 60 * 24 * 7)
		try? context.save()

		return server
	}

	private enum SessionCheck {
		case valid
		/// The server answered 401/403 (or there is no token): the session is invalid or expired.
		case rejected
		/// No answer (offline, timeout, server error): says nothing about the session.
		case unreachable
	}

	private static func checkSession(_ server: NafynServer) async -> SessionCheck {
		do {
			let _: NafynUser = try await server.send(User.me)
			return .valid
		} catch NafynError.unauthenticated {
			return .rejected
		} catch NafynError.server(let statusCode, _) where statusCode == 401 || statusCode == 403 {
			return .rejected
		} catch {
			return .unreachable
		}
	}
}
