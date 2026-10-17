// Made by Lumaa

import Foundation
import Security

/// The signed-in session (server URL + bearer token), mirrored into the Keychain so the Now Playing
/// remote-session extension — a separate process — can talk to the server on the user's behalf.
///
/// Both the app and the extension list a single `keychain-access-groups` entry, so items written without an
/// explicit access group land in (and are read from) that shared group. The value is never logged.
struct SharedSession: Codable, Equatable {
	var baseURL: URL
	var token: String

	private static let service = "fr.lumaa.Nafyn.session"
	private static let account = "active"

	private static var query: [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
	}

	static func load() -> SharedSession? {
		var query = self.query
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
		return try? JSONDecoder().decode(SharedSession.self, from: data)
	}

	@discardableResult
	static func save(_ session: SharedSession) -> Bool {
		guard let data = try? JSONEncoder().encode(session) else { return false }

		let update: [String: Any] = [kSecValueData as String: data]
		let status = SecItemUpdate(self.query as CFDictionary, update as CFDictionary)
		if status == errSecSuccess { return true }

		var add = self.query
		add[kSecValueData as String] = data
		// readable while the phone is locked: remote-session pushes arrive in the background
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
	}

	static func clear() {
		SecItemDelete(self.query as CFDictionary)
	}
}
