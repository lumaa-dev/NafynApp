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
				PaginatedList(paginator: paginator) { track in
					self.row(track)
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
			self.paginator = Paginator<MediaRow> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/library/tracks", page: page, limit: limit)
			}
		}
		.navigationTitle(String(localized: "tracks"))
		.toast(self.toast)
		.confirmationDialog(
			String(localized: "delete-track-confirm"),
			isPresented: Binding(get: { self.pendingDelete != nil }, set: { if !$0 { self.pendingDelete = nil } }),
			presenting: self.pendingDelete
		) { track in
			Button(String(localized: "delete"), role: .destructive) {
				self.delete(track)
			}
		}
	}

	@ViewBuilder
	private func row(_ track: MediaRow) -> some View {
		TrackRow(coverURL: track.coverArt.flatMap { URL(string: $0) }, title: track.title, subtitle: track.artistName, duration: track.duration, fileSize: track.fileSize) {
			PlayerEngine.shared.play(track, recordContext: RecordContext(type: .track, refId: track.id))
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				self.pendingDelete = track
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
		}
		.swipeActions(edge: .leading) {
			Button {
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [track.id])
			} label: {
				Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
			}
			.tint(DTColor.accentStart)
		}
		.contextMenu {
			Button {
				Navigator.shared.sheet = Navigator.Paths.addToPlaylist(mediaIds: [track.id])
			} label: {
				Label(String(localized: "add-to-playlist"), systemImage: "text.badge.plus")
			}

			Button {
				Navigator.shared.send(to: .libraryTrack(id: track.id))
			} label: {
				Label(String(localized: "view-track"), systemImage: "info.circle")
			}
		}
	}

	private func delete(_ track: MediaRow) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Library.remove(id: track.id)) as RemovedWithFileResponse
				self.paginator?.remove(where: { $0.id == track.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
