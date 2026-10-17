// Made by Lumaa

import UserNotifications

/// Attaches the cover art to Nafyn's alert pushes.
///
/// The server marks a push `mutable-content` when it carries `nafyn.imageUrl`. Everything here fails soft:
/// a bad URL, a slow server or a non-image response just delivers the notification without a picture.
final class NotificationService: UNNotificationServiceExtension {
	private var contentHandler: ((UNNotificationContent) -> Void)?
	private var bestAttempt: UNMutableNotificationContent?
	private var downloadTask: Task<Void, Never>?

	/// Short on purpose: the system gives the extension about 30 s in total and a missing picture is fine.
	private static let timeout: TimeInterval = 8
	private static let maxBytes = 10 * 1024 * 1024

	override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
		self.contentHandler = contentHandler
		self.bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

		guard let url = Self.imageURL(from: request.content.userInfo) else {
			contentHandler(request.content)
			return
		}

		self.downloadTask = Task {
			let attachment = await Self.attachment(for: url)
			if let attachment {
				self.bestAttempt?.attachments = [attachment]
			}
			self.finish()
		}
	}

	override func serviceExtensionTimeWillExpire() {
		self.downloadTask?.cancel()
		self.finish()
	}

	private func finish() {
		guard let handler = self.contentHandler, let content = self.bestAttempt else { return }
		self.contentHandler = nil
		handler(content)
	}

	/// `nafyn.imageUrl`, accepted only when it's https.
	private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
		guard let payload = userInfo["nafyn"] as? [String: Any],
		      let string = payload["imageUrl"] as? String,
		      let url = URL(string: string),
		      url.scheme?.lowercased() == "https"
		else { return nil }
		return url
	}

	private static func attachment(for url: URL) async -> UNNotificationAttachment? {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = self.timeout
		configuration.timeoutIntervalForResource = self.timeout
		let session = URLSession(configuration: configuration)
		defer { session.finishTasksAndInvalidate() }

		guard let (downloaded, response) = try? await session.download(from: url),
		      let http = response as? HTTPURLResponse, http.statusCode == 200,
		      let size = try? downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= self.maxBytes
		else { return nil }

		let fileExtension: String
		switch http.mimeType {
			case "image/png": fileExtension = "png"
			case "image/gif": fileExtension = "gif"
			case "image/webp": fileExtension = "webp"
			case "image/jpeg": fileExtension = "jpg"
			default: return nil
		}

		// the downloaded file has no extension, and the system decides the attachment type from it
		let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
		do {
			try FileManager.default.moveItem(at: downloaded, to: destination)
			return try UNNotificationAttachment(identifier: "cover", url: destination)
		} catch {
			return nil
		}
	}
}
