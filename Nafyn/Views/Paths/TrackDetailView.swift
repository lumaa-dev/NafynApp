// Made by Lumaa

import SwiftUI
import Safyn

struct TrackDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var toast = ToastState()
	@State private var isRequesting = false

	var trackId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.fetchTrackRelease(tid: self.trackId)
		} content: { track, reload in
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					self.head(track, reload: reload)
					self.footer(track.detail)
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
	private func head(_ release: TrackRelease, reload: @escaping () async -> Void) -> some View {
		let track = release.detail
		HStack(alignment: .top, spacing: 16) {
			CoverImage(url: track.info.coverArt.flatMap { URL(string: $0) })
				.frame(width: 130, height: 130)

			VStack(alignment: .leading, spacing: 6) {
				Text(track.info.title)
					.font(DTFont.serif(27))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(2)

				self.artistLink(track.info.artist)

				if let albumMbid = track.albumMbid {
					NavigationLink(value: Navigator.Paths.album(id: albumMbid)) {
						if let albumTitle = track.info.album?.title {
							Text(albumTitle)
						} else {
							Text("view-album")
						}
					}
					.font(DTFont.system(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				}

				if !release.released {
					UnreleasedSection(mbid: track.info.id, kind: .track, releaseDate: track.info.releaseDate, precision: release.precision, subscribed: release.subscribed, toast: self.toast) {
						Task { await reload() }
					}
					.padding(.top, 6)
				} else if track.info.inLibrary != true {
					Button {
						self.request(track: track, reload: reload)
					} label: {
						Text("request")
					}
					.buttonStyle(.filled())
					.disabled(self.isRequesting || NetworkMonitor.shared.isOffline)
					.padding(.top, 6)
				}
			}

			Spacer(minLength: 0)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private func artistLink(_ artist: ArtistRef) -> some View {
		switch artist {
			case .info(let info):
				NavigationLink(value: Navigator.Paths.artist(id: info.musicbrainzId)) {
					Text(info.name)
						.font(DTFont.serifItalic(20))
						.foregroundStyle(DTColor.textPrimary.opacity(0.75))
				}
			case .name(let name):
				Text(name)
					.font(DTFont.serifItalic(20))
					.foregroundStyle(DTColor.textPrimary.opacity(0.75))
		}
	}

	@ViewBuilder
	private func footer(_ track: TrackDetail) -> some View {
		HStack(spacing: 6) {
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
			}
		}
		.font(DTFont.system(16))
		.foregroundStyle(DTColor.textPrimary.opacity(0.5))
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
