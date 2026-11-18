// Made by Lumaa

import Foundation
import Safyn

extension RecentlyPlayedEntry {
	/// Where tapping this recently-played entry should navigate.
	///
	/// For `.track` entries, the server's own `refId` field is Nafyn's *internal* media ID, not the
	/// MusicBrainz recording ID `Track.get(tid:)` needs — confirmed against `recentlyPlayed.ts`, whose
	/// own `href` field correctly uses the recording ID while `refId` doesn't. `href`'s trailing path
	/// component (`/t/{id}`, `/a/{id}`, `/l/playlist/{id}`) is the authoritative ID, so prefer it and
	/// only fall back to `refId` if `href` doesn't parse as expected.
	var destination: Navigator.Paths {
		let hrefId = self.href.split(separator: "/").last.map(String.init)

		switch self.type {
			case .track:
				return .recentTrack(mediaId: self.refId, mbid: hrefId ?? self.refId)
			case .album:
				return .recentAlbum(id: hrefId ?? self.refId)
			case .playlist:
				return .playlist(id: hrefId ?? self.refId)
		}
	}
}

extension MusicCardEntry {
	/// Where tapping this card should navigate, or `nil` if it should play instead (owned tracks).
	var destination: Navigator.Paths? {
		switch self {
			case .recentlyPlayed(let entry):
				entry.destination
			case .album(let album):
				.libraryAlbum(id: album.id)
			case .media:
				nil
			case .playlist(let playlist):
				.playlist(id: playlist.id)
			case .info(let info):
				info.type == .track ? .track(id: info.id) : .album(id: info.id)
			case .artist(let artist):
				.artist(id: artist.musicbrainzId)
			case .pinned(let pin):
				switch pin.kind {
					case .track: .libraryTrack(id: pin.refId)
					case .album: .libraryAlbum(id: pin.refId)
					case .playlist: .playlist(id: pin.refId)
				}
		}
	}
}
