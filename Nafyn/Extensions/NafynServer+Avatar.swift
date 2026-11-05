// Made by Lumaa

import Foundation
import Safyn

extension NafynServer {
	/// A user's avatar. `NafynUser.avatar` / `UserProfile.avatar` is NOT a URL, it is a cache-busting version
	/// string the server bumps on every upload; the picture itself lives behind the `User.avatar(id:token:)`
	/// endpoint. Folding the version into the URL as a query item both builds the right URL and busts the image
	/// cache on every new upload. `nil` when the user has no avatar.
	func avatarURL(userId: String, version: String?) -> URL? {
		guard let version else { return nil }
		let endpoint = User.avatar(id: userId, token: self.authToken)
		guard var components = URLComponents(url: self.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		components.queryItems = endpoint.queries + [URLQueryItem(name: "v", value: version)]
		return components.url
	}
}
