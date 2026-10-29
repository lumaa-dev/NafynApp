// Made by Lumaa

import SwiftUI
import Safyn

/// Given a set of media IDs (a single track, or a whole album's owned tracks), lets the user pick which
/// of their playlists to add them to. Mirrors the web app's `PlaylistPickerModal.vue`.
struct AddToPlaylistSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var mediaIds: [String]

	@State private var paginator: Paginator<PlaylistRow>? = nil
	@State private var toast = ToastState()
	@State private var addingTo: String? = nil

	var body: some View {
		NavigationStack {
			Group {
				if let paginator {
					List(paginator.items) { playlist in
						Button {
							self.add(to: playlist)
						} label: {
							HStack {
								Text(playlist.title)
								Spacer()
								if self.addingTo == playlist.id {
									ProgressView()
										.tint(DTColor.textPrimary)
								}
							}
						}
						.disabled(self.addingTo != nil || NetworkMonitor.shared.isOffline)
						.onAppear { paginator.loadNextPageIfNeeded(currentItem: playlist) }
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
				let paginator = Paginator<PlaylistRow> { page, limit in
					try await server.fetchPaginated(path: "/api/v1/playlist", page: page, limit: limit)
				}
				self.paginator = paginator
				await paginator.reset()
			}
			.navigationTitle(String(localized: "add-to-playlist"))
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "cancel"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
			.toast(self.toast)
		}
		.sheetBackground()
	}

	private func add(to playlist: PlaylistRow) {
		guard let server, self.addingTo == nil else { return }
		self.addingTo = playlist.id

		Task {
			defer { self.addingTo = nil }
			do {
				_ = try await server.send(Playlist.addTracks(pid: playlist.id, mediaIds: self.mediaIds)) as [PlaylistEntryRow]
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
