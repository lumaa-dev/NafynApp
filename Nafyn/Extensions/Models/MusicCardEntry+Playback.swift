// Made by Lumaa

import Foundation
import Safyn

extension MusicCardEntry {
	/// Whether the card's Play / Shuffle menu applies. Artists have nothing to play, and a search result track or
	/// album that isn't in the library has no file to start.
	var isPlayable: Bool {
		switch self {
			case .artist:
				false
			case .info(let info):
				// a catalog album has tracks to play only once it is in the library
				info.type != .track && info.inLibrary == true
			case .recentlyPlayed, .album, .media, .playlist, .pinned:
				true
		}
	}

	/// The tracks this card stands for, in order, and the context to record the play under.
	func playbackQueue(server: NafynServer?) async throws -> (tracks: [MediaRow], context: RecordContext?) {
		switch self {
			case .media(let media):
				return ([media], RecordContext(type: .track, refId: media.id))

			case .album(let album):
				return (try await Self.libraryAlbumTracks(id: album.id, server: server), RecordContext(type: .album, refId: album.id))

			case .playlist(let playlist):
				return (try await Self.playlistTracks(id: playlist.id, server: server), RecordContext(type: .playlist, refId: playlist.id))

			case .info(let info):
				return (try await Self.catalogAlbumTracks(id: info.id, server: server), RecordContext(type: .album, refId: info.id))

			case .recentlyPlayed(let entry):
				let id = entry.destinationId
				switch entry.type {
					case .track:
						guard let server else { throw NafynError.unauthenticated }
						let response: LibraryTrackResponse = try await server.send(Library.track(id: entry.refId))
						return ([response.row], RecordContext(type: .track, refId: entry.refId))
					case .album:
						// a recently played album's `refId` is its library album ID
						return (try await Self.libraryAlbumTracks(id: entry.refId, server: server), RecordContext(type: .album, refId: entry.refId))
					case .playlist:
						return (try await Self.playlistTracks(id: id, server: server), RecordContext(type: .playlist, refId: id))
				}

			case .pinned(let pin):
				switch pin.kind {
					case .track:
						guard let server else { throw NafynError.unauthenticated }
						let response: LibraryTrackResponse = try await server.send(Library.track(id: pin.refId))
						return ([response.row], RecordContext(type: .track, refId: pin.refId))
					case .album:
						return (try await Self.libraryAlbumTracks(id: pin.refId, server: server), RecordContext(type: .album, refId: pin.refId))
					case .playlist:
						return (try await Self.playlistTracks(id: pin.refId, server: server), RecordContext(type: .playlist, refId: pin.refId))
				}

			case .artist:
				return ([], nil)
		}
	}

	/// An owned album's tracks; falls back to the downloaded ones when the server can't be reached.
	private static func libraryAlbumTracks(id: String, server: NafynServer?) async throws -> [MediaRow] {
		if let server {
			do {
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: id))
				return response.tracks
			} catch {
				let offline = DownloadManager.shared.downloads.filter { $0.albumId == id }
				if offline.isEmpty { throw error }
				return offline.map(\.mediaRow)
			}
		}
		return DownloadManager.shared.downloads.filter { $0.albumId == id }.map(\.mediaRow)
	}

	/// A MusicBrainz album's tracks that are in the library (the others have no file to play).
	private static func catalogAlbumTracks(id: String, server: NafynServer?) async throws -> [MediaRow] {
		guard let server else { throw NafynError.unauthenticated }
		let album = try await server.fetchAlbumDetail(aid: id)
		return album.tracks.compactMap { info in
			info.mediaId.map { info.asMediaRow(mediaId: $0, album: album) }
		}
	}

	private static func playlistTracks(id: String, server: NafynServer?) async throws -> [MediaRow] {
		guard let server else { throw NafynError.unauthenticated }
		var tracks: [MediaRow] = []
		var page = 1
		while true {
			let response = try await server.fetchPlaylistTracks(pid: id, page: page, limit: 100)
			tracks.append(contentsOf: response.items.map(\.media))
			guard response.hasMore else { break }
			page += 1
		}
		return tracks
	}
}

extension RecentlyPlayedEntry {
	/// The ID `destination` resolves: the trailing path component of `href`, else `refId`.
	var destinationId: String {
		self.href.split(separator: "/").last.map(String.init) ?? self.refId
	}
}
