// Made by Lumaa

import Foundation
import Safyn

extension TrackInfo {
	/// Builds a synthetic `MediaRow` for playback. `AlbumDetail.tracks` only carries `TrackInfo`, and
	/// Safyn has no endpoint to fetch the full `MediaRow` for one specific track of an album — mirrors
	/// the web app's own `toMediaRow()` helper, which does the same client-side reconstruction.
	///
	/// Only call this for a track that's actually playable (`mediaId != nil`).
	func asMediaRow(mediaId: String, album: AlbumDetail) -> MediaRow {
		MediaRow(
			id: mediaId,
			musicbrainzId: self.id,
			title: self.title,
			artistName: album.artist.name,
			artistMbid: nil,
			album: album.title,
			albumId: album.id,
			albumType: album.type,
			coverArt: album.coverArt,
			releaseDate: self.releaseDate.map { Int64($0.timeIntervalSince1970) },
			duration: self.duration,
			label: album.label,
			fingerprint: nil,
			amId: nil,
			fileSize: nil,
			addedAt: 0
		)
	}
}
