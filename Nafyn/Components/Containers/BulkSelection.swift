// Made by Lumaa

import SwiftUI
import Safyn

/// Which items of a "My tracks / albums / playlists" screen are ticked, and whether the screen is in
/// selection mode at all. Identifiers are the items' own IDs.
@Observable
final class BulkSelection {
	var isActive = false
	private(set) var ids: Set<String> = []

	var count: Int { self.ids.count }

	func contains(_ id: String) -> Bool {
		self.ids.contains(id)
	}

	func toggle(_ id: String) {
		if !self.ids.insert(id).inserted {
			self.ids.remove(id)
		}
	}

	func selectAll(_ ids: some Sequence<String>) {
		self.ids.formUnion(ids)
	}

	func clear() {
		self.ids = []
	}

	/// Animated, so the toolbar morphs between "Select" and the selecting buttons instead of swapping.
	func begin() {
		withAnimation(DTMotion.toolbar) {
			self.isActive = true
		}
	}

	func end() {
		withAnimation(DTMotion.toolbar) {
			self.isActive = false
			self.ids = []
		}
	}
}

/// The round tick drawn on a row or a card while its screen is selecting.
struct SelectionMark: View {
	let isSelected: Bool

	var body: some View {
		Image(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
			.font(DTFont.system(22))
			.foregroundStyle(self.isSelected ? DTColor.buttonFilled : DTColor.textPrimary.opacity(0.7))
			.background {
				// keeps the empty circle readable over a bright cover
				Circle()
					.fill(DTColor.surfaceSelect.opacity(0.6))
					.padding(2)
			}
			.accessibilityLabel(self.isSelected ? String(localized: "selected") : String(localized: "not-selected"))
	}
}

extension View {
	/// The toolbar of a screen with bulk actions: "Select" to start; then a menu (Select all, plus `actions`,
	/// which are disabled while nothing is ticked) and "Done".
	func bulkSelectionToolbar<Actions: View>(_ selection: BulkSelection, allIds: [String], @ViewBuilder actions: @escaping () -> Actions) -> some View {
		self.toolbar {
			if selection.isActive {
				ToolbarOverflowMenu {
					let allSelected = !allIds.isEmpty && allIds.allSatisfy { selection.contains($0) }

					Button {
						if allSelected {
							selection.clear()
						} else {
							selection.selectAll(allIds)
						}
					} label: {
						Label(allSelected ? String(localized: "deselect-all") : String(localized: "select-all"), systemImage: allSelected ? "circle" : "checkmark.circle")
					}
					.tint(Color.primary)

					Divider()

					Group {
						actions()
					}
					.disabled(selection.count == 0)
				}

				ToolbarItem(placement: .primaryAction) {
					Button {
						selection.end()
					} label: {
						Label(String(localized: "done"), systemImage: "checkmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			} else {
				ToolbarItem(placement: .primaryAction) {
					Button {
						selection.begin()
					} label: {
						Label(String(localized: "select"), systemImage: "checklist")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
					.disabled(allIds.isEmpty)
				}
			}
		}
	}

	/// The title shown above the list while selecting: how many are ticked.
	func bulkSelectionSubtitle(_ selection: BulkSelection) -> some View {
		self.navigationSubtitle(selection.isActive ? String(localized: "\(selection.count)-selected") : "")
	}
}

/// What a bulk action got done: the IDs that went through and the first failure, if any.
struct BulkResult {
	var succeeded: Set<String> = []
	var error: Error? = nil
}

/// The server work behind the bulk actions, run concurrently.
enum BulkActions {
	/// Removes tracks from the library, their downloads included.
	@MainActor
	static func removeTracks(_ ids: [String], server: NafynServer) async -> BulkResult {
		await self.run(ids) { id in
			try await server.removeFromLibrary(trackId: id)
		}
	}

	/// Removes every owned track of each album.
	@MainActor
	static func removeAlbums(_ ids: [String], server: NafynServer) async -> BulkResult {
		await self.run(ids) { id in
			try await server.removeLibraryAlbum(id: id)
		}
	}

	static func deletePlaylists(_ ids: [String], server: NafynServer) async -> BulkResult {
		await self.run(ids) { id in
			_ = try await server.send(Playlist.delete(pid: id)) as RemovedResponse
		}
	}

	/// The owned tracks of several albums, album by album. An album that can't be read is skipped; if none can
	/// be, the error is thrown.
	static func trackIds(ofAlbums albumIds: [String], server: NafynServer) async throws -> [String] {
		let (byAlbum, firstError) = await withTaskGroup(of: (String, [String]?, Error?).self) { group in
			for id in albumIds {
				group.addTask {
					do {
						let response: LibraryAlbumResponse = try await server.send(Library.album(id: id))
						return (id, response.tracks.map(\.id), nil)
					} catch {
						return (id, nil, error)
					}
				}
			}

			var byAlbum: [String: [String]] = [:]
			var firstError: Error? = nil
			for await (id, tracks, error) in group {
				if let tracks { byAlbum[id] = tracks }
				if firstError == nil { firstError = error }
			}
			return (byAlbum, firstError)
		}

		if byAlbum.isEmpty, let firstError { throw firstError }
		return albumIds.flatMap { byAlbum[$0] ?? [] }
	}

	private static func run(_ ids: [String], _ work: @escaping @Sendable (String) async throws -> Void) async -> BulkResult {
		await withTaskGroup(of: (String, Error?).self) { group in
			for id in ids {
				group.addTask {
					do {
						try await work(id)
						return (id, nil)
					} catch {
						return (id, error)
					}
				}
			}

			var result = BulkResult()
			for await (id, error) in group {
				if let error {
					result.error = result.error ?? error
				} else {
					result.succeeded.insert(id)
				}
			}
			return result
		}
	}
}

/// "Pin" or "Unpin" for a whole selection: Unpin once every ticked item is pinned, Pin otherwise.
struct BulkPinButton: View {
	@Environment(\.server) private var server: NafynServer?

	let targets: [PinTarget]
	let toast: ToastState
	let onDone: () -> Void

	var body: some View {
		let allPinned = !self.targets.isEmpty && self.targets.allSatisfy { PinStore.shared.isPinned($0) }

		Button {
			let targets = self.targets
			Task { @MainActor in
				do {
					try await PinStore.shared.setPinned(!allPinned, targets, server: self.server)
					self.toast.success(allPinned ? String(localized: "unpinned") : String(localized: "pinned-toast"))
					self.onDone()
				} catch {
					self.toast.failure(error)
				}
			}
		} label: {
			Label(allPinned ? String(localized: "unpin") : String(localized: "pin"), systemImage: allPinned ? "pin.slash" : "pin")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)
	}
}
