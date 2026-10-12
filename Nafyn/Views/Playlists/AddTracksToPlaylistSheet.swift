// Made by Lumaa

import SwiftUI
import Safyn

/// Given a playlist, browse the user's owned tracks and add them one at a time. Mirrors the web app's
/// `AddTracksModal.vue`.
struct AddTracksToPlaylistSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var playlistId: String
	var existingMediaIds: Set<String>
	var onAdded: () -> Void

	@State private var paginator: Paginator<MediaRow>? = nil
	@State private var toast = ToastState()
	@State private var addingId: String? = nil
	@State private var addedIds: Set<String> = []

	var body: some View {
		NavigationStack {
			Group {
				if let paginator {
					List(paginator.items) { track in
						self.row(track)
							.onAppear { paginator.loadNextPageIfNeeded(currentItem: track) }
					}
					.listStyle(.plain)
					.scrollEdgeEffectStyle(.soft, for: .all)
				} else {
					List {
						SkeletonTrackRows(showsCover: false)
					}
					.listStyle(.plain)
				}
			}
			.background(DTColor.background.ignoresSafeArea())
			.task {
				guard self.paginator == nil, let server else { return }
				let paginator = Paginator<MediaRow> { page, limit in
					try await server.fetchPaginated(path: "/api/v1/library/tracks", page: page, limit: limit)
				}
				self.paginator = paginator
				await paginator.reset()
			}
			.navigationTitle(String(localized: "add-tracks"))
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button(String(localized: "done")) { self.dismiss() }
						.tint(Color.primary)
				}
			}
			.toast(self.toast)
		}
	}

	@ViewBuilder
	private func row(_ track: MediaRow) -> some View {
		let alreadyIn = self.existingMediaIds.contains(track.id) || self.addedIds.contains(track.id)

		Button {
			self.add(track)
		} label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(track.title)
						.font(DTFont.serif(18))
						.foregroundStyle(DTColor.textPrimary)
					Text(track.artistName)
						.font(DTFont.serif(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				}

				Spacer()

				if self.addingId == track.id {
					ProgressView()
						.tint(DTColor.textPrimary)
				} else if alreadyIn {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(DTColor.statusSuccess)
				} else {
					Image(systemName: "plus.circle")
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
				}
			}
		}
		.disabled(alreadyIn || self.addingId != nil || NetworkMonitor.shared.isOffline)
	}

	private func add(_ track: MediaRow) {
		guard let server, self.addingId == nil, !self.existingMediaIds.contains(track.id), !self.addedIds.contains(track.id) else { return }
		self.addingId = track.id

		Task {
			defer { self.addingId = nil }
			do {
				_ = try await server.send(Playlist.addTracks(pid: self.playlistId, mediaIds: [track.id])) as [PlaylistEntryRow]
				self.addedIds.insert(track.id)
				self.onAdded()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
