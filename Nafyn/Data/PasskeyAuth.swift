// Made by Lumaa

import AuthenticationServices
import Safyn
import UIKit

/// Wraps Apple's WebAuthn ceremonies (`AuthenticationServices`) for Nafyn's passkey endpoints.
///
/// Platform passkeys are normally scoped to a relying-party domain declared via an Associated Domains
/// entitlement. Nafyn can't declare that statically since every self-hosted server has its own domain —
/// registration/assertion still work without it, but the system can't offer iCloud Keychain autofill or
/// cross-device sync parity unless the server's own domain hosts a matching `apple-app-site-association`.
@MainActor
final class PasskeyAuth: NSObject {
	enum PasskeyError: LocalizedError {
		case malformedOptions
		case cancelled

		var errorDescription: String? {
			switch self {
				case .malformedOptions:
					String(localized: "passkey-malformed-options")
				case .cancelled:
					String(localized: "passkey-cancelled")
			}
		}
	}

	private var continuation: CheckedContinuation<ASAuthorization, Error>?

	/// Registers a new passkey for the currently authenticated user.
	static func register(server: NafynServer, label: String?) async throws {
		let options = try await server.send(User.passkeyRegisterOptions) as JSONValue
		guard
			let challenge = options.string("challenge").flatMap(Data.init(base64urlEncoded:)),
			let user = options.object?["user"],
			let userId = user.string("id").flatMap(Data.init(base64urlEncoded:))
		else { throw PasskeyError.malformedOptions }

		let rpId = options.string("rp", "id") ?? server.instance.baseURL.host ?? ""
		let userName = user.string("name") ?? label ?? ""

		let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
		let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userId)

		let authorization = try await PasskeyAuth().perform(request)
		guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
			throw PasskeyError.malformedOptions
		}

		let response = JSONValue.object([
			"id": .string(credential.credentialID.base64urlEncodedString()),
			"rawId": .string(credential.credentialID.base64urlEncodedString()),
			"type": .string("public-key"),
			"authenticatorAttachment": .string("platform"),
			"clientExtensionResults": .object([:]),
			"response": .object([
				"clientDataJSON": .string(credential.rawClientDataJSON.base64urlEncodedString()),
				"attestationObject": .string((credential.rawAttestationObject ?? Data()).base64urlEncodedString())
			])
		])

		_ = try await server.sendRaw(User.registerPasskey(response: response, label: label))
	}

	/// Logs in via passkey against `instance`, returning the same shape as `Auth.login`.
	static func login(instance: NafynInstance) async throws -> AuthResponse {
		let server = NafynServer(instance: instance)
		let options = try await server.send(Auth.passkeyLoginOptions) as JSONValue

		// `passkeyLoginOptions` carries a server-issued challenge ID alongside the WebAuthn options; the
		// exact nesting isn't pinned down by the Safyn docs, so this checks both a flat shape and one
		// wrapped under an "options" key.
		let root = options
		let nested = options.object?["options"]
		guard
			let challengeId = root.string("challengeId") ?? nested?.string("challengeId"),
			let challenge = (root.string("challenge") ?? nested?.string("challenge")).flatMap(Data.init(base64urlEncoded:))
		else { throw PasskeyError.malformedOptions }

		let rpId = root.string("rpId") ?? nested?.string("rpId") ?? instance.baseURL.host ?? ""

		let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
		let request = provider.createCredentialAssertionRequest(challenge: challenge)

		let authorization = try await PasskeyAuth().perform(request)
		guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
			throw PasskeyError.malformedOptions
		}

		var responseFields: [String: JSONValue] = [
			"clientDataJSON": .string(credential.rawClientDataJSON.base64urlEncodedString()),
			"authenticatorData": .string(credential.rawAuthenticatorData.base64urlEncodedString()),
			"signature": .string(credential.signature.base64urlEncodedString())
		]
		if let userID = credential.userID, !userID.isEmpty {
			responseFields["userHandle"] = .string(userID.base64urlEncodedString())
		}

		let response = JSONValue.object([
			"id": .string(credential.credentialID.base64urlEncodedString()),
			"rawId": .string(credential.credentialID.base64urlEncodedString()),
			"type": .string("public-key"),
			"authenticatorAttachment": .string("platform"),
			"clientExtensionResults": .object([:]),
			"response": .object(responseFields)
		])

		return try await server.send(Auth.passkeyLogin(challengeId: challengeId, response: response))
	}

	private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
		try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			let controller = ASAuthorizationController(authorizationRequests: [request])
			controller.delegate = self
			controller.presentationContextProvider = self
			controller.performRequests()
		}
	}
}

extension PasskeyAuth: ASAuthorizationControllerDelegate {
	func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
		self.continuation?.resume(returning: authorization)
		self.continuation = nil
	}

	func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
		if let authError = error as? ASAuthorizationError, authError.code == .canceled {
			self.continuation?.resume(throwing: PasskeyError.cancelled)
		} else {
			self.continuation?.resume(throwing: error)
		}
		self.continuation = nil
	}
}

extension PasskeyAuth: ASAuthorizationControllerPresentationContextProviding {
	func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
		UIApplication.shared.connectedScenes
			.compactMap { ($0 as? UIWindowScene)?.keyWindow }
			.first ?? ASPresentationAnchor()
	}
}

private extension JSONValue {
	var object: [String: JSONValue]? {
		if case .object(let dict) = self { return dict }
		return nil
	}

	func string(_ key: String) -> String? {
		guard case .string(let value)? = self.object?[key] else { return nil }
		return value
	}

	func string(_ key: String, _ nestedKey: String) -> String? {
		self.object?[key]?.string(nestedKey)
	}
}

private extension Data {
	init?(base64urlEncoded string: String) {
		var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
		while base64.count % 4 != 0 {
			base64.append("=")
		}
		guard let data = Data(base64Encoded: base64) else { return nil }
		self = data
	}

	func base64urlEncodedString() -> String {
		self.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
}
