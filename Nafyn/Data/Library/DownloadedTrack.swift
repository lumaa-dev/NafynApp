// Made by Lumaa

import Foundation
import SwiftData
import Safyn

/// One track downloaded for offline playback, persisted alongside ``AuthInfo`` in the app's shared
/// `ModelContainer`. The actual audio file lives under ``DownloadManager``'s downloads directory,
/// named `fileName` — this row is just the metadata needed to render it and to resolve that file.
@Model
final class DownloadedTrack {
	/// Nafyn's internal media ID — also this row's identity, so a track can't be downloaded twice.
	@Attribute(.unique) var id: String

	var title: String
	var artistName: String
	var albumId: String
	var album: String?
	var coverArt: String?
	var duration: Double

	/// Filename of the downloaded audio file within ``DownloadManager``'s downloads directory.
	var fileName: String
	var fileSize: Int64
	var downloadedAt: Date

	init(id: String, title: String, artistName: String, albumId: String, album: String?, coverArt: String?, duration: Double, fileName: String, fileSize: Int64, downloadedAt: Date) {
		self.id = id
		self.title = title
		self.artistName = artistName
		self.albumId = albumId
		self.album = album
		self.coverArt = coverArt
		self.duration = duration
		self.fileName = fileName
		self.fileSize = fileSize
		self.downloadedAt = downloadedAt
	}

	/// A `MediaRow` reconstructed from this row's cached metadata — enough for `PlayerEngine` to play
	/// it (which resolves the audio itself from the local file, not any of these fields) and to render
	/// a queue entry. Fields Nafyn never needed to keep offline (MusicBrainz IDs, release date, label,
	/// …) are left empty/nil rather than re-fetched.
	var mediaRow: MediaRow {
		MediaRow(
			id: self.id,
			musicbrainzId: "",
			title: self.title,
			artistName: self.artistName,
			artistMbid: nil,
			album: self.album,
			albumId: self.albumId,
			albumType: nil,
			coverArt: self.coverArt,
			releaseDate: nil,
			duration: self.duration,
			label: nil,
			fingerprint: nil,
			amId: nil,
			fileSize: self.fileSize,
			addedAt: Int64(self.downloadedAt.timeIntervalSince1970 * 1000)
		)
	}
}
