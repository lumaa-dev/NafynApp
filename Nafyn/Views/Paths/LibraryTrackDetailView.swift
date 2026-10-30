// Made by Lumaa

import SwiftUI
import Safyn

/// An owned track, fetched via `Library.track(id:)` by Nafyn's internal media ID: Play only, no Request
/// button — distinct from ``TrackDetailView``, which fetches MusicBrainz metadata by recording ID.
struct LibraryTrackDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var trackId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Library.track(id: self.trackId)) as LibraryTrackResponse
		} content: { response, _ in
			LibraryTrackDetailContent(response: response)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct LibraryTrackDetailContent: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss
	@Environment(\.colorScheme) private var colorScheme

	@State private var toast = ToastState()
	@State private var showDeleteConfirm = false

	let response: LibraryTrackResponse

	private var track: MediaRow { self.response.row }

	var body: some View {
		let palette = CoverPalette(imageColors: self.response.imageColors, colorScheme: self.colorScheme)

		// Regular width (Duo inner display, iPad) or a phone held sideways: the cover and titles in one pane,
		// Play and the details in the other.
		AdaptiveCoverDetail(palette: palette, spacing: 20) {
			self.header(palette: palette)
		} compact: {
			self.actions(palette: palette)
			self.footer(palette: palette)
		} primary: {
			EmptyView()
		} secondary: {
			self.actions(palette: palette)
			self.footer(palette: palette)
		}
		.toast(self.toast)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Menu {
					if DownloadManager.shared.isDownloaded(trackId: self.track.id) {
						Button(role: .destructive) {
							self.removeDownload()
						} label: {
							Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
						}
						.tint(DTColor.buttonDanger)
					} else {
						Button {
							DownloadManager.shared.downloadTrack(self.track)
						} label: {
							Label(String(localized: "download"), systemImage: "arrow.down.circle")
						}
						.tint(Color.primary)
						.disabled(DownloadManager.shared.isDownloading(trackId: self.track.id) || NetworkMonitor.shared.isOffline)
					}

					Button(role: .destructive) {
						self.showDeleteConfirm = true
					} label: {
						Label(String(localized: "delete"), systemImage: "trash")
					}
					.tint(DTColor.buttonDanger)
					.disabled(NetworkMonitor.shared.isOffline)
				} label: {
					Label(String(localized: "more"), systemImage: "ellipsis")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
			}
		}
		// attached to the toolbar's host view: triggered from the toolbar menu
		.alert(String(localized: "delete-track-confirm"), isPresented: self.$showDeleteConfirm) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.delete()
			}
		}
	}

	private func header(palette: CoverPalette) -> some View {
		CoverHeader(url: self.track.setCoverSize(1000), palette: palette) {
			Text(self.track.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)
				.lineLimit(2)

			Text(self.track.artistName)
				.font(DTFont.serifItalic(20))
				.foregroundStyle(palette.primary)
		}
	}

	@ViewBuilder
	private func actions(palette: CoverPalette) -> some View {
		Button {
			self.play()
		} label: {
			Label(String(localized: "play"), systemImage: "play.fill")
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.filled())

		NavigationLink(value: Navigator.Paths.libraryAlbum(id: self.track.albumId)) {
			HStack {
				Text(self.track.album ?? String(localized: "view-album"))
					.multilineTextAlignment(.leading)

				Spacer(minLength: 0)

				Image(systemName: "chevron.right")
					.font(DTFont.system(14, weight: .semibold))
			}
			.font(DTFont.system(17))
			.foregroundStyle(palette.primary)
		}
	}

	@ViewBuilder
	private func footer(palette: CoverPalette) -> some View {
		FlowLayout(spacing: 6) {
			if self.track.duration > 0 {
				Text(TrackRow<EmptyView>.formattedDuration(self.track.duration))
			}
			if let releaseDate = self.track.releaseDateValue {
				Text("·")
				Text(releaseDate.formatted(date: .abbreviated, time: .omitted))
			}
			if let label = self.track.label {
				Text("·")
				Text(label)
			}
		}
		.font(DTFont.system(16))
		.foregroundStyle(palette.secondary)
	}

	private func play() {
		PlaybackSource.play(self.track, recordContext: RecordContext(type: .track, refId: self.track.id))
	}

	private func removeDownload() {
		guard let entry = DownloadManager.shared.downloads.first(where: { $0.id == self.track.id }) else { return }
		DownloadManager.shared.delete(entry)
	}

	private func delete() {
		guard let server else { return }
		Task {
			do {
				try await server.removeFromLibrary(self.track)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
