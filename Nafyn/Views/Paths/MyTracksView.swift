// Made by Lumaa

import SwiftUI
import Safyn

struct MyTracksView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var toast = ToastState()
	@State private var pendingDelete: MediaRow? = nil
	@State private var paginator: Paginator<MediaRow>? = nil

	var body: some View {
		Group {
			if let paginator {
				List {
					ForEach(self.mergedTracks) { track in
						self.row(track)
							.listRowBackground(Color.clear)
							.onAppear { paginator.loadNextPageIfNeeded(currentItem: track) }
					}

					if paginator.isLoadingPage {
						SkeletonTrackRows(count: self.mergedTracks.isEmpty ? 8 : 2)
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
					}

					if let error = paginator.error, self.mergedTracks.isEmpty {
						VStack(spacing: 12) {
							Text(error.localizedDescription)
								.font(DTFont.system(16))
								.foregroundStyle(DTColor.textPrimary.opacity(0.7))
								.multilineTextAlignment(.center)

							Button(String(localized: "retry")) {
								Task { await paginator.reset() }
							}
							.buttonStyle(.hollow())
						}
						.frame(maxWidth: .infinity)
						.padding()
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
					}
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
				.scrollEdgeEffectStyle(.soft, for: .all)
				.contentColumn()
				.background(DTColor.background.ignoresSafeArea())
				.refreshable {
					await paginator.reset()
				}
			} else {
				List {
					SkeletonTrackRows()
						.listRowBackground(Color.clear)
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
			}
		}
		.task {
			guard self.paginator == nil, let server else { return }
			let paginator = Paginator<MediaRow> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/library/tracks", page: page, limit: limit)
			}
			self.paginator = paginator
			await paginator.reset()
		}
		.navigationTitle(String(localized: "tracks"))
		.toast(self.toast)
		.alert(
			String(localized: "delete-track-confirm"),
			isPresented: Binding(get: { self.pendingDelete != nil }, set: { if !$0 { self.pendingDelete = nil } }),
			presenting: self.pendingDelete
		) { track in
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.delete(track)
			}
		}
	}

	/// `paginator.items` merged with every downloaded track, so offline tracks stay visible in the same
	/// list instead of the screen falling back to a bare network-error message while offline.
	private var mergedTracks: [MediaRow] {
		var seen: Set<String> = []
		var result: [MediaRow] = []

		for track in self.paginator?.items ?? [] where seen.insert(track.id).inserted {
			result.append(track)
		}
		for entry in DownloadManager.shared.downloads where seen.insert(entry.id).inserted {
			result.append(entry.mediaRow)
		}

		return result.sorted { $0.addedAtDate > $1.addedAtDate }
	}

	@ViewBuilder
	private func row(_ track: MediaRow) -> some View {
		TrackRow(coverURL: track.coverArt.flatMap { URL(string: $0) }, title: track.title, subtitle: track.artistName, duration: track.duration, fileSize: track.fileSize, onTap: {
			PlaybackSource.play(track, recordContext: RecordContext(type: .track, refId: track.id))
		}) {
			if DownloadManager.shared.isDownloaded(trackId: track.id) {
				Image(systemName: "arrow.down.circle.fill")
					.foregroundStyle(DTColor.textPrimary.opacity(0.4))
			}
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				self.pendingDelete = track
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
			.disabled(NetworkMonitor.shared.isOffline)
		}
		.swipeActions(edge: .leading) {
			Button {
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [track.id])
			} label: {
				Label(String(localized: "add"), systemImage: "text.badge.plus")
			}
			.tint(DTColor.accentStart)
		}
		.contextMenu {
			TrackMenuItems(track: track) {
				self.pendingDelete = track
			}
		}
	}

	private func delete(_ track: MediaRow) {
		guard let server else { return }
		Task {
			do {
				try await server.removeFromLibrary(track)
				self.paginator?.remove(where: { $0.id == track.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
