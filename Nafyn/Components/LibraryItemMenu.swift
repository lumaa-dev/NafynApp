// Made by Lumaa

import SwiftUI
import Safyn

/// Something the user owns that a card, chart row or list entry can stand for, known only by its ID.
/// One place that knows how to play it, and how to delete it, so every surface offers the same menu.
enum LibraryItem: Hashable {
	case album(id: String)
	case track(id: String)

	/// The tracks to queue, and the context to record the play under.
	func playbackQueue(server: NafynServer?) async throws -> (tracks: [MediaRow], context: RecordContext?) {
		guard let server else { throw NafynError.unauthenticated }

		switch self {
			case .album(let id):
				let response: LibraryAlbumResponse = try await server.send(Library.album(id: id))
				return (response.tracks, RecordContext(type: .album, refId: id))
			case .track(let id):
				let response: LibraryTrackResponse = try await server.send(Library.track(id: id))
				return ([response.row], RecordContext(type: .track, refId: id))
		}
	}

	@MainActor
	func delete(server: NafynServer) async throws {
		switch self {
			case .album(let id):
				try await server.removeLibraryAlbum(id: id)
			case .track(let id):
				try await server.removeFromLibrary(trackId: id)
		}
	}

	fileprivate var confirmation: String {
		switch self {
			case .album: String(localized: "delete-album-confirm")
			case .track: String(localized: "delete-track-confirm")
		}
	}
}

typealias PlaybackQueueLoader = () async throws -> (tracks: [MediaRow], context: RecordContext?)

private struct LibraryItemMenuHost<Content: View>: View {
	let content: Content

	@Environment(\.server) private var server: NafynServer?

	let item: LibraryItem?
	let playQueue: PlaybackQueueLoader?
	let onRemoved: (() -> Void)?

	@State private var toast = ToastState()
	@State private var isConfirmingDelete = false

	var body: some View {
		self.content
			.contextMenu {
				self.menu
			}
			.toast(self.toast)
			.alert(self.item?.confirmation ?? "", isPresented: self.$isConfirmingDelete) {
				Button(String(localized: "cancel"), role: .cancel) {}
				Button(String(localized: "delete"), role: .destructive) {
					self.delete()
				}
			}
	}

	@ViewBuilder
	private var menu: some View {
		if let playQueue = self.playQueue {
			ControlGroup {
				Button {
					self.play(shuffle: false, loader: playQueue)
				} label: {
					Label(String(localized: "play"), systemImage: "play.fill")
				}
				.tint(Color.primary)

				Button {
					self.play(shuffle: true, loader: playQueue)
				} label: {
					Label(String(localized: "shuffle"), systemImage: "shuffle")
				}
				.tint(Color.primary)
			}
		}

		if case .track(let id)? = self.item {
			TrackMenuItems(trackId: id, onDelete: {
				self.isConfirmingDelete = true
			})
		} else if case .album? = self.item {
			Button(role: .destructive) {
				self.isConfirmingDelete = true
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.buttonDanger)
			.disabled(NetworkMonitor.shared.isOffline)
		}
	}

	private func play(shuffle: Bool, loader: @escaping PlaybackQueueLoader) {
		Task {
			do {
				var (queue, context) = try await loader()
				guard !queue.isEmpty else { return }
				if shuffle {
					queue.shuffle()
				}
				PlaybackSource.play(queue[0], queue: queue, recordContext: context)
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func delete() {
		guard let item = self.item, let server else { return }
		Task {
			do {
				try await item.delete(server: server)
				self.onRemoved?()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

extension View {
	/// The long-press menu of anything that can be played and/or lives in the user's library: Play / Shuffle
	/// (when `play` is given), then the track items or Delete for `item`, with the delete confirmation.
	/// `onRemoved` runs after a successful delete so the owner can drop the entry from its list.
	func libraryItemMenu(item: LibraryItem?, play: PlaybackQueueLoader?, onRemoved: (() -> Void)? = nil) -> some View {
		LibraryItemMenuHost(content: self, item: item, playQueue: play, onRemoved: onRemoved)
	}
}

extension RankedEntity {
	/// The owned item behind a chart row, for the shared menu. Artists and playlists have none.
	var libraryItem: LibraryItem? {
		switch self.entityType {
			case .track: .track(id: self.entityId)
			case .album: .album(id: self.entityId)
			case .artist, .playlist: nil
		}
	}
}
