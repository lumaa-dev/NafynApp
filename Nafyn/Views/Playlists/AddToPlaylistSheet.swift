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
	/// Several playlists can be picked; the toolbar's check adds to all of them.
	@State private var selected: Set<String> = []
	@State private var isAdding = false

	var body: some View {
		NavigationStack {
			Group {
				if let paginator {
					List(paginator.items) { playlist in
						Button {
							self.toggle(playlist.id)
						} label: {
							self.row(playlist)
						}
						.tint(Color.primary)
						.disabled(self.isAdding)
						.accessibilityAddTraits(self.selected.contains(playlist.id) ? .isSelected : [])
						.onAppear { paginator.loadNextPageIfNeeded(currentItem: playlist) }
					}
					.listStyle(.plain)
					.scrollEdgeEffectStyle(.soft, for: .all)
				} else {
					List {
						SkeletonTrackRows()
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
			.navigationBarTitleDisplayMode(.inline)
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

				ToolbarItem(placement: .confirmationAction) {
					if self.isAdding {
						ProgressView()
							.tint(DTColor.textPrimary)
					} else {
						Button {
							self.addToSelected()
						} label: {
							Label(String(localized: "add-to-\(self.selected.count)-playlists"), systemImage: "checkmark")
								.labelStyle(.iconOnly)
						}
						.tint(Color.primary)
						.disabled(self.selected.isEmpty || NetworkMonitor.shared.isOffline)
					}
				}
			}
			.toast(self.toast)
		}
		.sheetBackground()
	}

	/// The playlist's own picture (DESIGN.md: selection screens show what they list the same way as elsewhere), its
	/// title, and a tick when picked - not only a colour.
	private func row(_ playlist: PlaylistRow) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: playlist.image != nil ? MusicCardEntry.playlistImageURL(pid: playlist.id, server: self.server) : nil)
				.frame(width: 48, height: 48)

			Text(playlist.title)
				.font(DTFont.system(17))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)

			Spacer(minLength: 0)

			Image(systemName: self.selected.contains(playlist.id) ? "checkmark.circle.fill" : "circle")
				.font(DTFont.system(22))
				.foregroundStyle(self.selected.contains(playlist.id) ? DTColor.textPrimary : DTColor.textPrimary.opacity(0.4))
				.contentTransition(.symbolEffect(.replace))
		}
		.contentShape(Rectangle())
	}

	private func toggle(_ id: String) {
		Haptics.selection()
		if self.selected.contains(id) {
			self.selected.remove(id)
		} else {
			self.selected.insert(id)
		}
	}

	/// One call per playlist, concurrently; the ones that failed stay picked so another try only sends those.
	private func addToSelected() {
		guard let server, !self.isAdding, !self.selected.isEmpty else { return }
		self.isAdding = true
		let ids = self.selected
		let mediaIds = self.mediaIds

		Task {
			defer { self.isAdding = false }
			let failures = await withTaskGroup(of: (String, Error?).self) { group in
				for id in ids {
					group.addTask {
						do {
							_ = try await server.send(Playlist.addTracks(pid: id, mediaIds: mediaIds)) as [PlaylistEntryRow]
							return (id, nil)
						} catch {
							return (id, error)
						}
					}
				}
				var failed: [(String, Error)] = []
				for await (id, error) in group {
					if let error { failed.append((id, error)) }
				}
				return failed
			}

			if let first = failures.first {
				self.selected = Set(failures.map(\.0))
				self.toast.failure(first.1)
			} else {
				Haptics.success()
				self.dismiss()
			}
		}
	}
}
