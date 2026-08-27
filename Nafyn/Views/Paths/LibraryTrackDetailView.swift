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
			return try await server.send(Library.track(id: self.trackId)) as MediaRow
		} content: { track, _ in
			LibraryTrackDetailContent(track: track)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct LibraryTrackDetailContent: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	@State private var toast = ToastState()
	@State private var showDeleteConfirm = false

	let track: MediaRow

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				self.head
				self.footer
			}
			.padding()
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.toast(self.toast)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Menu {
					Button(role: .destructive) {
						self.showDeleteConfirm = true
					} label: {
						Label(String(localized: "delete"), systemImage: "trash")
					}
				} label: {
					Image(systemName: "ellipsis")
				}
				.tint(Color.primary)
			}
		}
		.confirmationDialog(String(localized: "delete-track-confirm"), isPresented: self.$showDeleteConfirm) {
			Button(String(localized: "delete"), role: .destructive) {
				self.delete()
			}
		}
	}

	@ViewBuilder
	private var head: some View {
		HStack(alignment: .top, spacing: 16) {
			CoverImage(url: self.track.coverArt.flatMap { URL(string: $0) })
				.frame(width: 130, height: 130)

			VStack(alignment: .leading, spacing: 6) {
				Text(self.track.title)
					.font(DTFont.serif(27))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(2)

				Text(self.track.artistName)
					.font(DTFont.serifItalic(20))
					.foregroundStyle(DTColor.textPrimary.opacity(0.75))

				NavigationLink(value: Navigator.Paths.libraryAlbum(id: self.track.albumId)) {
					Text(self.track.album ?? String(localized: "view-album"))
				}
				.font(DTFont.system(15))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

				Button {
					self.play()
				} label: {
					Label(String(localized: "play"), systemImage: "play.fill")
				}
				.buttonStyle(.filled())
				.padding(.top, 6)
			}

			Spacer(minLength: 0)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var footer: some View {
		HStack(spacing: 6) {
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
		.foregroundStyle(DTColor.textPrimary.opacity(0.5))
	}

	private func play() {
		PlayerEngine.shared.play(self.track, recordContext: RecordContext(type: .track, refId: self.track.id))
	}

	private func delete() {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Library.remove(id: self.track.id)) as RemovedWithFileResponse
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
