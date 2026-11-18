// Made by Lumaa

import Foundation
import SwiftData

@Model
final class AuthInfo: Codable, Identifiable {
	var server: String
	var username: String
	var password: String
	var token: String
	var tokenExpire: Date
	var defaultAuth: Bool

	var id: String {
		"\(server)-\(username)&\(self.password)"
	}

	init(server: String, username: String, password: String, token: String, tokenExpire: Date, defaultAuth: Bool) {
		self.server = server
		self.username = username
		self.password = password
		self.token = token
		self.tokenExpire = tokenExpire
		self.defaultAuth = defaultAuth
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.server = try container.decode(String.self, forKey: .server)
		self.username = try container.decode(String.self, forKey: .username)
		self.password = try container.decode(String.self, forKey: .password)
		self.token = try container.decode(String.self, forKey: .token)
		let expireUnix: Double = try container.decode(Double.self, forKey: .tokenExpire)
		self.tokenExpire = Date(timeIntervalSince1970: expireUnix)
		self.defaultAuth = try container.decode(Bool.self, forKey: .defaultAuth)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(self.server, forKey: .server)
		try container.encode(self.username, forKey: .username)
		try container.encode(self.password, forKey: .password)
		try container.encode(self.token, forKey: .token)
		try container.encode(self.tokenExpire.timeIntervalSince1970, forKey: .tokenExpire)
		try container.encode(self.defaultAuth, forKey: .defaultAuth)
	}

	enum CodingKeys: CodingKey {
		case server
		case username
		case password
		case token
		case tokenExpire
		case defaultAuth
	}
}
