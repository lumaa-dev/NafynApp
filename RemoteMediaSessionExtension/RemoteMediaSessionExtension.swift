// Made by Lumaa

import Foundation
import ExtensionFoundation
import NowPlaying
import Observation
import UIKit
import Safyn

/// System Now Playing for a Nafyn Unity master playing on another device (a browser tab, say).
///
/// The server starts and updates the session by push; this extension answers with the session's content
/// and turns the system's play/pause/next/previous/seek/volume commands into Nafyn Unity slave commands.
@main
struct NafynRemoteSessionExtension: RemoteMediaSessionExtension {
	var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
		RemoteMediaSessionExtensionConfiguration(extension: self)
	}

	func session(_ attributes: NafynRemoteSessionAttributes) async throws -> NafynRemoteSession {
		NafynRemoteSession(attributes: attributes)
	}
}

/// One remote session. The framework caches the instance and routes later updates and commands to it, so
/// the server connection is set up once here and reused.
@Observable
@MainActor
final class NafynRemoteSession: @MainActor RemoteMediaSessionRepresentable {
	let id: String
	private var attributes: NafynRemoteSessionAttributes

	@ObservationIgnored private let link = UnityCommandLink()
	@ObservationIgnored private var tokenTask: Task<Void, Never>?

	init(attributes: NafynRemoteSessionAttributes) {
		self.id = attributes.id
		self.attributes = attributes
		self.startReportingPushToken()
	}

	deinit {
		self.tokenTask?.cancel()
	}

	func update(_ attributes: NafynRemoteSessionAttributes) {
		// `end` pushes carry only the id: keep the last content and let the system tear the session down
		self.attributes = attributes
	}

	// MARK: - Content

	var content: (any MediaContentRepresentable)? {
		guard let track = self.attributes.currentTrack else { return nil }
		let link = self.link

		return MusicContent(
			id: track.id,
			songTitle: track.title,
			artistName: track.artist,
			albumName: track.album ?? String(),
			type: .audio,
			duration: track.duration > 0 ? .finite(track.duration) : nil,
			artwork: Artwork(id: track.artworkURL ?? track.id) { _ in
				try await ArtworkRepresentation(data: link.artworkData(for: track))
			}
		)
	}

	var playbackSnapshot: MediaPlaybackSnapshot? {
		guard self.attributes.currentTrack != nil else { return nil }
		// the system extrapolates from `elapsedTime` at `timestamp` while playing, so no per-second pushes
		return MediaPlaybackSnapshot(
			state: self.attributes.isPlaying == true ? .playing() : .paused,
			elapsedTime: self.attributes.elapsedTime ?? 0,
			timestamp: self.attributes.timestampDate ?? .now
		)
	}

	// MARK: - Commands

	var commands: [MediaCommand] {
		let link = self.link
		let index = self.attributes.currentTrackIndex ?? 0
		let count = self.attributes.queueCount ?? 0

		// Unity has one `togglePlay` mutator, so play/pause only send it when they'd actually change state
		return [
			.play { [weak self] in
				guard let self, self.attributes.isPlaying != true else { return }
				try await link.send(.togglePlay)
			},
			.pause { [weak self] in
				guard let self, self.attributes.isPlaying == true else { return }
				try await link.send(.togglePlay)
			},
			.togglePlayPause { try await link.send(.togglePlay) },
			.next { try await link.send(.next) }
				.enabled(index < count - 1),
			.previous { try await link.send(.prev) }
				.enabled(index > 0),
			.seekToPosition { time in
				try await link.send(.seek(time))
			},
		]
	}

	var devices: [MediaDevice] {
		let link = self.link
		return (self.attributes.devices ?? []).map { device in
			MediaDevice(
				id: device.id,
				name: device.name,
				type: Self.deviceType(device.type),
				capabilities: [
					.absoluteVolume(Float(min(max(device.volume, 0), 1))) { level in
						try await link.send(.setVolume(Double(level)))
					},
				]
			)
		}
	}

	private static func deviceType(_ raw: String) -> MediaDevice.DeviceType {
		switch raw {
			case "phone": .phone
			case "tablet": .tablet
			case "speaker": .speaker
			default: .desktop
		}
	}

	// MARK: - Update token

	/// The update/end token is per session and only the process that owns the session sees it, so it's
	/// reported from here: `POST /user/activities` with `kind: nowplaying`, `refId` = the session id.
	private func startReportingPushToken() {
		let id = self.id
		let link = self.link

		self.tokenTask = Task { [weak self] in
			if let token = self?.pushToken {
				await link.registerSessionToken(token, sessionId: id)
			}
			guard let updates = self?.pushTokenUpdates else { return }
			for await token in updates {
				await link.registerSessionToken(token, sessionId: id)
			}
		}
	}
}

/// The extension's own line to the server. It's a separate process, so it rebuilds the connection from the
/// session the app mirrored into the shared Keychain (`SharedSession`).
actor UnityCommandLink {
	private var server: NafynServer?
	private var socket: NafynUnitySocket?

	private func connectedServer() async throws -> NafynServer {
		if let server { return server }
		guard let session = SharedSession.load() else { throw NafynError.unauthenticated }
		let instance = try await NafynInstance.connect(appName: "Nafyn", to: session.baseURL)
		let server = NafynServer(instance: instance, authToken: session.token)
		self.server = server
		return server
	}

	/// Sends `command` to the master as a Unity slave (`{"type":"command","action":…,"payload":…}`).
	func send(_ command: UnityCommand) async throws {
		let socket = try await self.openSocket()
		socket.send(command)
	}

	private func openSocket() async throws -> NafynUnitySocket {
		if let socket { return socket }
		let socket = try await self.connectedServer().unitySocket()
		socket.onClose = { [weak self] _, _ in
			Task { await self?.dropSocket() }
		}
		socket.onError = { [weak self] _ in
			Task { await self?.dropSocket() }
		}
		socket.connect()
		self.socket = socket
		return socket
	}

	private func dropSocket() {
		self.socket?.disconnect()
		self.socket = nil
	}

	func registerSessionToken(_ token: Data, sessionId: String) async {
		guard let server = try? await self.connectedServer() else { return }
		#if DEBUG
		let environment = APNsEnvironment.sandbox
		#else
		let environment = APNsEnvironment.production
		#endif
		// a 404 means the session is already over; there's nothing to retry either way
		_ = try? await server.sendRaw(User.registerActivityToken(kind: .nowPlaying, refId: sessionId, token: token.map { String(format: "%02x", $0) }.joined(), environment: environment))
	}

	/// The cover for the system UI: the public `artworkURL` when the server sent one, otherwise the
	/// authenticated uploaded cover of the library track.
	func artworkData(for track: NafynRemoteSessionAttributes.Track) async throws -> Data {
		if let string = track.artworkURL, let url = URL(string: string), url.scheme == "https" {
			let (data, _) = try await URLSession.shared.data(from: url)
			return data
		}
		let server = try await self.connectedServer()
		return try await server.sendRaw(Library.cover(id: track.id))
	}
}
