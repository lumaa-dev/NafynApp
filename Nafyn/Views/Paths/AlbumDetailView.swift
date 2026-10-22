// Made by Lumaa

import SwiftUI
import Safyn

struct AlbumDetailView: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.zoomNamespace) private var zoomNamespace: Namespace.ID?

	@State private var toast = ToastState()
	@State private var isRequesting = false

	var albumId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.fetchAlbumDetail(aid: self.albumId)
		} content: { album, reload in
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					self.header(album)

					if let description = album.description, !description.isEmpty {
						Text(description)
							.font(DTFont.system(18))
							.foregroundStyle(DTColor.textPrimary.opacity(0.8))
					}

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

					VStack(spacing: 0) {
						ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
							self.trackRow(track, album: album, reload: reload)

							if index < album.tracks.count - 1 {
								Divider()
									.overlay(DTColor.borderSelect)
							}
						}
					}

					self.footer(album)
				}
				.padding()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.background(DTColor.background.ignoresSafeArea())
			.toast(self.toast)
		}
		.navigationBarTitleDisplayMode(.inline)
	}

	@ViewBuilder
	private func header(_ album: AlbumDetail) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			CoverImage(url: album.coverArt.flatMap { URL(string: $0) })
				.frame(width: 200, height: 200)
				.frame(maxWidth: .infinity)

			HStack(spacing: 8) {
				if let type = album.type {
					Text(type == .ep ? String(localized: "ep") : String(localized: "album"))
						.font(DTFont.system(14, weight: .semibold))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background(DTColor.surfaceInput, in: Capsule())
				}
			}

			Text(album.title)
				.font(DTFont.serif(31))
				.foregroundStyle(DTColor.textPrimary)

			self.artistLink(album.artist)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private func artistLink(_ artist: ArtistRef) -> some View {
		switch artist {
			case .info(let info):
				NavigationLink(value: Navigator.Paths.artist(id: info.musicbrainzId)) {
					Text(info.name)
						.font(DTFont.serif(20))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
				}
			case .name(let name):
				Text(name)
					.font(DTFont.serif(20))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
		}
	}

	@ViewBuilder
	private func trackRow(_ track: TrackInfo, album: AlbumDetail, reload: @escaping () async -> Void) -> some View {
		TrackRow(
			index: String(Int(track.trackNumber)),
			title: track.title,
			duration: track.duration,
			dimmed: !track.released,
			verticalPadding: 12,
			onTap: track.mediaId != nil ? { self.play(track, album: album) } : nil
		) {
			if !track.released, let releaseDate = track.releaseDate {
				// a track that's still unreleased on an album that is: no download, just when it lands
				ReleaseCountdown(releaseDate: releaseDate, compact: true) {
					Task { await reload() }
				}
			} else if !track.requested && !track.inLibrary && track.released {
				Button {
					self.request(track: track, reload: reload)
				} label: {
					Image(systemName: "arrow.down.circle")
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
				}
				.buttonStyle(.plain)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
		.contextMenu {
			if let mediaId = track.mediaId {
				Button {
					Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [mediaId])
				} label: {
					Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
				}
			}
		}
	}

	@ViewBuilder
	private func footer(_ album: AlbumDetail) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			if let releaseDate = album.releaseDate {
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			if let label = album.label {
				Text(label)
			}
			if let url = URL(string: "https://musicbrainz.org/release-group/\(album.id)") {
				Link(String(localized: "view-on-musicbrainz"), destination: url)
			}
		}
		.font(DTFont.system(16))
		.foregroundStyle(DTColor.textPrimary.opacity(0.5))
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
		PlayerEngine.shared.play(media, queue: queue, recordContext: RecordContext(type: .album, refId: album.id))
	}
}
