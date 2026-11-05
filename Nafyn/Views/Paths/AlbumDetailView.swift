// Made by Lumaa

import SwiftUI
import Safyn

struct AlbumDetailView: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.zoomNamespace) private var zoomNamespace: Namespace.ID?
	@Environment(\.colorScheme) private var colorScheme

	@State private var toast = ToastState()
	@State private var isRequesting = false

	var albumId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.fetchAlbumDetail(aid: self.albumId)
		} content: { album, reload in
			let palette = CoverPalette(imageColors: album.imageColors, colorScheme: self.colorScheme)

			// Regular width (Duo inner display, iPad) or a phone held sideways: cover, blurb and details in one
			// pane, the actions and the track list in the other, instead of everything stacked in one column.
			AdaptiveCoverDetail(palette: palette) {
				self.header(album, palette: palette)
			} compact: {
				self.description(album, palette: palette)
				self.actions(album, reload: reload)
				self.trackList(album, palette: palette, reload: reload)
				self.footer(album, palette: palette)
			} primary: {
				self.description(album, palette: palette)
				self.footer(album, palette: palette)
			} secondary: {
				self.actions(album, reload: reload)
				self.trackList(album, palette: palette, reload: reload)
			}
			.toast(self.toast)
			.toolbar {
				// pinning needs the album in the library; the Request button covers the rest
				if album.inLibrary {
					ToolbarItem(placement: .primaryAction) {
						PinMenuButton(target: .album(album.id))
							.labelStyle(.iconOnly)
					}
				}
			}
		}
		.navigationBarTitleDisplayMode(.inline)
	}

	private func header(_ album: AlbumDetail, palette: CoverPalette) -> some View {
		CoverHeader(url: album.coverArt?.coverArtURL(size: 1000), palette: palette) {
			if let type = album.type {
				Text(type == .ep ? String(localized: "ep") : String(localized: "album"))
					.font(DTFont.system(14, weight: .semibold))
					.foregroundStyle(palette.secondary)
			}

			Text(album.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)

			self.artistLink(album.artist, palette: palette)
		}
	}

	@ViewBuilder
	private func description(_ album: AlbumDetail, palette: CoverPalette) -> some View {
		if let description = album.description, !description.isEmpty {
			Text(description)
				.font(DTFont.system(18))
				.foregroundStyle(palette.secondary)
		}
	}

	/// Request button, or the countdown while the album is still unreleased.
	@ViewBuilder
	private func actions(_ album: AlbumDetail, reload: @escaping () async -> Void) -> some View {
		if album.released {
			if !album.inLibrary {
				Button {
					self.request(album: album, reload: reload)
				} label: {
					Text("request")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())
				.disabled(self.isRequesting || album.requested || NetworkMonitor.shared.isOffline)
			}
		} else {
			UnreleasedSection(mbid: album.id, kind: .album, releaseDate: album.releaseDate, precision: album.releaseDatePrecision, subscribed: album.subscribed, toast: self.toast) {
				Task { await reload() }
			}
		}
	}

	@ViewBuilder
	private func trackList(_ album: AlbumDetail, palette: CoverPalette, reload: @escaping () async -> Void) -> some View {
		let groups = Self.discGroups(of: album)

		VStack(spacing: 0) {
			ForEach(groups, id: \.number) { group in
				// disc headers only when the album actually spans several discs
				if groups.count > 1 {
					DiscHeader(number: group.number, title: group.title, isFirst: group.number == groups.first?.number, palette: palette)
				}

				ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
					self.trackRow(track, album: album, palette: palette, reload: reload)

					if index < group.tracks.count - 1 {
						Divider()
							.overlay(palette.secondary.opacity(0.3))
					}
				}
			}
		}
	}

	/// One disc's tracks, in the server's order, with the disc's own title when it has one.
	private struct DiscGroup {
		let number: Double
		let title: String?
		let tracks: [TrackInfo]
	}

	private static func discGroups(of album: AlbumDetail) -> [DiscGroup] {
		let byDisc = Dictionary(grouping: album.tracks, by: \.discNumber)
		return byDisc.keys.sorted().map { number in
			let title = album.discs.first { $0.number == number }?.title
			return DiscGroup(number: number, title: title?.isEmpty == false ? title : nil, tracks: byDisc[number] ?? [])
		}
	}

	@ViewBuilder
	private func artistLink(_ artist: ArtistRef, palette: CoverPalette) -> some View {
		switch artist {
			case .info(let info):
				NavigationLink(value: Navigator.Paths.artist(id: info.musicbrainzId)) {
					Text(info.name)
						.font(DTFont.serif(20))
						.foregroundStyle(palette.primary)
				}
			case .name(let name):
				Text(name)
					.font(DTFont.serif(20))
					.foregroundStyle(palette.primary)
		}
	}

	@ViewBuilder
	private func trackRow(_ track: TrackInfo, album: AlbumDetail, palette: CoverPalette, reload: @escaping () async -> Void) -> some View {
		let row = TrackRow(
			index: String(Int(track.trackNumber)),
			title: track.title,
			duration: track.duration,
			dimmed: !track.released,
			verticalPadding: 12,
			onTap: track.mediaId != nil ? { self.play(track, album: album) } : nil
		) {
			if !track.released {
				if album.released, let releaseDate = track.releaseDate {
					// a track that's still unreleased on an album that is: no download, just when it lands.
					// On an unreleased album the album's own countdown already says it, so rows stay bare.
					ReleaseCountdown(releaseDate: releaseDate, compact: true) {
						Task { await reload() }
					}
				}
			} else if !track.requested && !track.inLibrary {
				Button {
					self.request(track: track, reload: reload)
				} label: {
					Image(systemName: "arrow.down.circle")
						.foregroundStyle(palette.primary)
				}
				.buttonStyle(.plain)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}

		if let mediaId = track.mediaId {
			// a track the user owns gets the menu every owned track has
			row.libraryItemMenu(
				item: .track(id: mediaId),
				play: { [server = self.server] in try await LibraryItem.track(id: mediaId).playbackQueue(server: server) },
				onRemoved: { Task { await reload() } }
			)
		} else if track.released, !track.requested, !track.inLibrary {
			// the row's own download arrow, for when the row is held instead of tapped
			row.contextMenu {
				Button {
					self.request(track: track, reload: reload)
				} label: {
					Label(String(localized: "request"), systemImage: "arrow.down.circle")
				}
				.tint(Color.primary)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		} else {
			row
		}
	}

	@ViewBuilder
	private func footer(_ album: AlbumDetail, palette: CoverPalette) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			if let releaseDate = album.releaseDate {
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			if let label = album.label {
				Text(label)
			}
			if let url = URL(string: "https://musicbrainz.org/release-group/\(album.id)") {
				Link(String(localized: "view-on-musicbrainz"), destination: url)
					.foregroundStyle(palette.primary)
			}
		}
		.font(DTFont.system(16))
		.foregroundStyle(palette.secondary)
	}

	private func request(album: AlbumDetail, reload: @escaping () async -> Void) {
		guard let server, !self.isRequesting else { return }
		self.isRequesting = true

		Task {
			defer { self.isRequesting = false }
			do {
				_ = try await server.send(Request.create(id: album.id, type: .album)) as NafynRequest
				self.toast.success(String(localized: "request-sent"))
				await PushManager.shared.requestAuthorizationIfNeeded()
			} catch {
				await self.handleRequestFailure(error, reload: reload)
			}
		}
	}

	private func request(track: TrackInfo, reload: @escaping () async -> Void) {
		guard let server else { return }

		Task {
			do {
				_ = try await server.send(Request.create(id: track.id, type: .track)) as NafynRequest
				self.toast.success(String(localized: "request-sent"))
				await PushManager.shared.requestAuthorizationIfNeeded()
			} catch {
				await self.handleRequestFailure(error, reload: reload)
			}
		}
	}

	/// A release the server still considers unreleased (our clock was ahead, or the date moved): say so and
	/// reload, which swaps Request for the countdown.
	private func handleRequestFailure(_ error: Error, reload: () async -> Void) async {
		if let error = error as? NafynError, error.isNotReleasedYet {
			self.toast.failure(error)
			await reload()
		} else {
			self.toast.failure(error)
		}
	}

	private func play(_ track: TrackInfo, album: AlbumDetail) {
		guard let mediaId = track.mediaId else { return }

		let queue = album.tracks.compactMap { info -> MediaRow? in
			guard let id = info.mediaId else { return nil }
			return info.asMediaRow(mediaId: id, album: album)
		}
		let media = track.asMediaRow(mediaId: mediaId, album: album)
		PlaybackSource.play(media, queue: queue, recordContext: RecordContext(type: .album, refId: album.id))
	}
}
