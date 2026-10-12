// Made by Lumaa

import Foundation
import SwiftData
import BackgroundTasks
import Safyn

/// Global singleton offline-download engine: downloads tracks/albums/playlists the user owns onto
/// disk for offline playback, surfacing progress through `BackgroundTasks`' `BGContinuedProcessingTask`
/// (a continued-processing task that starts in the foreground, keeps running if the app backgrounds,
/// and shows a system Live Activity with progress — a person can cancel it from there too).
///
/// One `BGContinuedProcessingTaskRequest` is submitted per `enqueue(_:title:subtitle:)` call; this
/// class's own `pendingBatches` queue (not the request itself, which can't carry arbitrary payloads)
/// is what tells the launch handler which tracks that particular invocation is for — submissions are
/// processed FIFO, matching the system's `.queue` scheduling strategy.
@Observable
final class DownloadManager {
	static let shared = DownloadManager()

	static let taskIdentifier = "fr.lumaa.Nafyn.offlineDownload"

	private(set) var downloads: [DownloadedTrack] = []
	private(set) var downloadingTrackIds: Set<String> = []
	private(set) var lastError: String? = nil

	private weak var server: NafynServer?
	private let context: ModelContext
	private var pendingBatches: [DownloadBatch] = []

	private struct DownloadBatch {
		let id = UUID()
		let tracks: [MediaRow]
		let title: String
		let subtitle: String
	}

	private init() {
		self.context = ModelContext(NafynApp.container)
		self.refresh()
		BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
			guard let continuedTask = task as? BGContinuedProcessingTask else {
				task.setTaskCompleted(success: false)
				return
			}
			// `register`'s handler can fire on an arbitrary queue; every mutation below touches this
			// class's `@Observable` state and its `ModelContext` (not thread-safe on its own), so it
			// all needs to happen on the same actor as every UI-triggered call (`enqueue`, `delete`, …).
			Task { @MainActor in
				self?.run(continuedTask)
			}
		}
	}

	func configure(server: NafynServer) {
		self.server = server
	}

	// MARK: - Downloads directory

	/// Under Application Support rather than Documents, and excluded from iCloud/iTunes backup —
	/// downloaded audio is a re-fetchable cache, not user data worth backing up.
	static let downloadsDirectory: URL = {
		let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("OfflineDownloads", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

		var excludedDir = dir
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		try? excludedDir.setResourceValues(values)

		return dir
	}()

	// MARK: - Query

	func isDownloaded(trackId: String) -> Bool {
		self.downloads.contains(where: { $0.id == trackId })
	}

	func isDownloading(trackId: String) -> Bool {
		self.downloadingTrackIds.contains(trackId)
	}

	/// The local file for an already-downloaded track, or `nil` if it isn't downloaded (or its file
	/// went missing on disk). `PlayerEngine` checks this before building a streaming URL.
	func localFileURL(for trackId: String) -> URL? {
		guard let entry = self.downloads.first(where: { $0.id == trackId }) else { return nil }
		let url = Self.downloadsDirectory.appendingPathComponent(entry.fileName)
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	var totalBytes: Int64 {
		self.downloads.reduce(0) { $0 + $1.fileSize }
	}

	// MARK: - Enqueue

	func downloadTrack(_ track: MediaRow) {
		self.enqueue([track], title: track.title, subtitle: track.artistName)
	}

	func downloadAlbum(id: String, title: String) {
		guard let server else { return }
		Task {
			do {
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: id))
				self.enqueue(response.tracks, title: title, subtitle: String(localized: "download-album-subtitle"))
			} catch {
				self.lastError = error.localizedDescription
			}
		}
	}

	func downloadPlaylist(id: String, title: String) {
		guard let server else { return }
		Task {
			do {
				var tracks: [MediaRow] = []
				var page = 1
				while true {
					let response = try await server.fetchPlaylistTracks(pid: id, page: page, limit: 100)
					tracks.append(contentsOf: response.items.map(\.media))
					guard response.hasMore else { break }
					page += 1
				}
				self.enqueue(tracks, title: title, subtitle: String(localized: "download-playlist-subtitle"))
			} catch {
				self.lastError = error.localizedDescription
			}
		}
	}

	@MainActor
	private func enqueue(_ tracks: [MediaRow], title: String, subtitle: String) {
		let newTracks = tracks.filter { !self.isDownloaded(trackId: $0.id) && !self.isDownloading(trackId: $0.id) }
		guard !newTracks.isEmpty else { return }

		self.downloadingTrackIds.formUnion(newTracks.map(\.id))
		let batch = DownloadBatch(tracks: newTracks, title: title, subtitle: subtitle)
		self.pendingBatches.append(batch)

		let request = BGContinuedProcessingTaskRequest(identifier: Self.taskIdentifier, title: title, subtitle: subtitle)
		do {
			try BGTaskScheduler.shared.submit(request)
		} catch {
			self.lastError = error.localizedDescription
			self.downloadingTrackIds.subtract(newTracks.map(\.id))
			self.pendingBatches.removeAll(where: { $0.id == batch.id })
		}
	}

	// MARK: - Background task execution

	@MainActor
	private func run(_ task: BGContinuedProcessingTask) {
		guard !self.pendingBatches.isEmpty else {
			task.setTaskCompleted(success: true)
			return
		}
		let batch = self.pendingBatches.removeFirst()

		var isExpired = false
		task.expirationHandler = { [weak self] in
			isExpired = true
			Task { @MainActor in self?.lastError = String(localized: "download-expired") }
		}

		let progress = task.progress
		progress.totalUnitCount = Int64(batch.tracks.count)

		Task { @MainActor in
			var succeeded = true

			for (index, track) in batch.tracks.enumerated() {
				guard !isExpired else {
					succeeded = false
					break
				}

				task.updateTitle(batch.title, subtitle: String(format: String(localized: "download-progress-subtitle"), index + 1, batch.tracks.count))

				do {
					try await self.downloadFile(for: track)
				} catch {
					succeeded = false
					self.lastError = error.localizedDescription
				}

				self.downloadingTrackIds.remove(track.id)
				progress.completedUnitCount = Int64(index + 1)
			}

			self.refresh()
			task.setTaskCompleted(success: succeeded && !isExpired)
		}
	}

	private func downloadFile(for track: MediaRow) async throws {
		guard let server else { throw NafynError.unauthenticated }

		let endpoint = Library.stream(id: track.id, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else {
			throw NafynError.invalidURL
		}
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		guard let url = components.url else { throw NafynError.invalidURL }

		var request = URLRequest(url: url)
		if let authToken = server.authToken {
			request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		}

		let tempURL: URL
		let response: URLResponse
		do {
			(tempURL, response) = try await URLSession.shared.download(for: request)
		} catch {
			throw NafynError.transport(error.localizedDescription)
		}

		guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
			throw NafynError.invalidResponse
		}

		let fileName = "\(track.id).\(Self.fileExtension(forMimeType: httpResponse.mimeType))"
		let destination = Self.downloadsDirectory.appendingPathComponent(fileName)

		try? FileManager.default.removeItem(at: destination)
		try FileManager.default.moveItem(at: tempURL, to: destination)

		let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0

		// Network fetch and file move above deliberately run off the main actor (this function isn't
		// `@MainActor`-isolated) — only the `ModelContext` write, which isn't safe to touch from more
		// than one thread, hops back to join every other access to it (`enqueue`/`run`/`delete`/…).
		try await MainActor.run {
			let entry = DownloadedTrack(
				id: track.id,
				title: track.title,
				artistName: track.artistName,
				albumId: track.albumId,
				album: track.album,
				coverArt: track.coverArt,
				duration: track.duration,
				fileName: fileName,
				fileSize: fileSize,
				downloadedAt: .now
			)
			self.context.insert(entry)
			try self.context.save()
		}
	}

	private static func fileExtension(forMimeType mimeType: String?) -> String {
		switch mimeType {
			case "audio/mpeg": "mp3"
			case "audio/flac", "audio/x-flac": "flac"
			case "audio/ogg", "audio/vorbis": "ogg"
			case "audio/wav", "audio/x-wav", "audio/wave": "wav"
			default: "m4a" // audio/mp4, audio/x-m4a, and anything else AVFoundation already streams fine
		}
	}

	// MARK: - Deletion

	func delete(_ entry: DownloadedTrack) {
		let url = Self.downloadsDirectory.appendingPathComponent(entry.fileName)
		try? FileManager.default.removeItem(at: url)
		self.context.delete(entry)
		try? self.context.save()
		self.refresh()
	}

	func deleteAll() {
		for entry in self.downloads {
			let url = Self.downloadsDirectory.appendingPathComponent(entry.fileName)
			try? FileManager.default.removeItem(at: url)
			self.context.delete(entry)
		}
		try? self.context.save()
		self.refresh()
	}

	private func refresh() {
		let descriptor = FetchDescriptor<DownloadedTrack>(sortBy: [SortDescriptor(\.downloadedAt, order: .reverse)])
		self.downloads = (try? self.context.fetch(descriptor)) ?? []
	}
}
