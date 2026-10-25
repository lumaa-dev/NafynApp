// Made by Lumaa

import SwiftUI
import Safyn

struct TrackDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	@Environment(\.colorScheme) private var colorScheme

	@State private var toast = ToastState()
	@State private var isRequesting = false

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
		}
		.navigationBarTitleDisplayMode(.inline)
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
			Button {
				self.request(track: track, reload: reload)
			} label: {
				Text("request")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())
			.disabled(self.isRequesting || track.requested == true || NetworkMonitor.shared.isOffline)
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
