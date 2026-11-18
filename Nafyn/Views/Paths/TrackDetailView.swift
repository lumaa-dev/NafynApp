// Made by Lumaa

import SwiftUI
import Safyn

struct TrackDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	@Environment(\.colorScheme) private var colorScheme

	@State private var toast = ToastState()
	@State private var isRequesting = false
	/// "Share as Image" (DESIGN.md "Sharing": iOS only, one item at a time).
	@State private var sharedImage: ShareCardContent?

	var trackId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.fetchTrackRelease(tid: self.trackId)
		} content: { track, reload in
			let palette = CoverPalette(imageColors: track.detail.info.imageColors, colorScheme: self.colorScheme)

			// Regular width (Duo inner display, iPad) or a phone held sideways: the cover and titles in one
			// pane, the request action and the details in the other.
			AdaptiveCoverDetail(palette: palette, spacing: 20) {
				self.header(track.detail, palette: palette)
			} compact: {
				self.actions(track, palette: palette, reload: reload)
				self.footer(track.detail, palette: palette)
			} primary: {
				EmptyView()
			} secondary: {
				self.actions(track, palette: palette, reload: reload)
				self.footer(track.detail, palette: palette)
			}
			.toast(self.toast)
			.toolbar {
				// DESIGN.md "Track/Album Detail view": an overflow menu with the actions of the track's row, minus the
				// ones that would navigate back to this very screen
				ToolbarOverflowMenu {
						if let albumMbid = track.detail.albumMbid {
							Button {
								Navigator.shared.send(to: .album(id: albumMbid))
							} label: {
								Label(String(localized: "view-album"), systemImage: "square.stack")
							}
							.tint(Color.primary)
						}

						if let artistId = Self.artistId(of: track.detail.info.artist) {
							Button {
								Navigator.shared.send(to: .artist(id: artistId))
							} label: {
								Label(String(localized: "view-artist"), systemImage: "person")
							}
							.tint(Color.primary)
						}

						ExternalLinkMenuItems(item: ExternalShareItem(title: track.detail.info.title, artist: track.detail.info.artist.name))

						CatalogShareMenu(path: "t/\(track.detail.info.id)", title: track.detail.info.title) {
							self.sharedImage = ShareCardContent(title: track.detail.info.title, subtitle: track.detail.info.artist.name, coverURL: track.detail.info.coverArt?.coverArtURL(size: 1000))
						}
				}
			}
		}
		.navigationBarTitleDisplayMode(.inline)
		.onDisappear { PreviewPlayer.shared.stop() }
		.sheet(item: self.$sharedImage) { content in
			ShareImageSheet(content: content)
		}
	}

	private static func artistId(of artist: ArtistRef) -> String? {
		if case .info(let info) = artist { return info.musicbrainzId }
		return nil
	}

	private func header(_ track: TrackDetail, palette: CoverPalette) -> some View {
		CoverHeader(url: track.info.coverArt?.coverArtURL(size: 1000), palette: palette) {
			Text(track.info.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)
				.lineLimit(2)

			self.artistLink(track.info.artist, palette: palette)
		}
	}

	@ViewBuilder
	private func actions(_ release: TrackRelease, palette: CoverPalette, reload: @escaping () async -> Void) -> some View {
		let track = release.detail

		if let albumMbid = track.albumMbid {
			NavigationLink(value: Navigator.Paths.album(id: albumMbid)) {
				HStack {
					if let albumTitle = track.info.album?.title {
						Text(albumTitle)
							.multilineTextAlignment(.leading)
					} else {
						Text("view-album")
					}

					Spacer(minLength: 0)

					Image(systemName: "chevron.right")
						.font(DTFont.system(14, weight: .semibold))
				}
				.font(DTFont.system(17))
				.foregroundStyle(palette.primary)
			}
		}

		if !release.released {
			UnreleasedSection(mbid: track.info.id, kind: .track, releaseDate: track.info.releaseDate, precision: release.precision, subscribed: release.subscribed, toast: self.toast) {
				Task { await reload() }
			}
		} else if track.info.inLibrary != true {
			let preview = PreviewPlayer.shared
			let unavailable = preview.unavailableIds.contains(track.info.id)

			HStack(spacing: 10) {
				Button {
					self.request(track: track, reload: reload)
				} label: {
					Text("request")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())
				.disabled(self.isRequesting || track.requested == true || NetworkMonitor.shared.isOffline)

				// not in the library: its 30 s iTunes preview
				Button {
					preview.toggle(tid: track.info.id, server: self.server)
				} label: {
					Text(preview.isActive(track.info.id) ? "stop-preview" : "play-preview")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())
				.disabled(unavailable || NetworkMonitor.shared.isOffline)
			}
			.fixedSize(horizontal: false, vertical: true)

			// DESIGN.md "Error messages": where the preview should have started
			if unavailable {
				Text("no-preview")
					.font(DTFont.system(15))
					.foregroundStyle(palette.secondary)
			}
		}
	}

	@ViewBuilder
	private func artistLink(_ artist: ArtistRef, palette: CoverPalette) -> some View {
		switch artist {
			case .info(let info):
				NavigationLink(value: Navigator.Paths.artist(id: info.musicbrainzId)) {
					Text(info.name)
						.font(DTFont.serifItalic(20))
						.foregroundStyle(palette.primary)
				}
			case .name(let name):
				Text(name)
					.font(DTFont.serifItalic(20))
					.foregroundStyle(palette.primary)
		}
	}

	@ViewBuilder
	private func footer(_ track: TrackDetail, palette: CoverPalette) -> some View {
		FlowLayout(spacing: 6) {
			if track.info.duration > 0 {
				Text(TrackRow<EmptyView>.formattedDuration(track.info.duration))
			}
			if let releaseDate = track.info.releaseDate {
				Text("·")
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			if let label = track.info.label {
				Text("·")
				Text(label)
			}
			Text("·")
			if let url = URL(string: "https://musicbrainz.org/recording/\(track.info.id)") {
				Link(String(localized: "view-on-musicbrainz"), destination: url)
					.foregroundStyle(palette.primary)
			}
		}
		.font(DTFont.system(16))
		.foregroundStyle(palette.secondary)
	}

	private func request(track: TrackDetail, reload: @escaping () async -> Void) {
		guard let server, !self.isRequesting else { return }
		self.isRequesting = true

		Task {
			defer { self.isRequesting = false }
			do {
				_ = try await server.send(Request.create(id: track.info.id, type: .track)) as NafynRequest
				RecommendationFeedback.shared.requested(recordingId: track.info.id)
				self.toast.success(String(localized: "request-sent"))
				await PushManager.shared.requestAuthorizationIfNeeded()
			} catch {
				self.toast.failure(error)
				// the server still considers it unreleased: reload swaps Request for the countdown
				if let error = error as? NafynError, error.isNotReleasedYet {
					await reload()
				}
			}
		}
	}
}
