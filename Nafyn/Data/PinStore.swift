// Made by Lumaa

import SwiftUI
import Safyn

/// Something that can be pinned: a track (media ID), an album (release-group MBID) or a playlist (ID).
struct PinTarget: Hashable, Sendable {
	let kind: PinKind
	let refId: String

	static func track(_ id: String) -> PinTarget { PinTarget(kind: .track, refId: id) }
	static func album(_ id: String) -> PinTarget { PinTarget(kind: .album, refId: id) }
	static func playlist(_ id: String) -> PinTarget { PinTarget(kind: .playlist, refId: id) }
}

extension LibraryItem {
	/// The pin that stands for this owned item.
	var pinTarget: PinTarget {
		switch self {
			case .album(let id): .album(id)
			case .track(let id): .track(id)
		}
	}
}

/// The signed-in user's pins (`Pins.list`), newest first, shared by the Library grid, every menu and the
/// bulk actions. A pin or unpin shows up in `isPinned` straight away; the list itself is re-read from the
/// server afterwards, because a new pin needs the title and cover the server knows.
@Observable
final class PinStore {
	static let shared = PinStore()

	private(set) var items: [PinnedItem] = []

	/// What `isPinned` answers from: the server's list plus pins/unpins still on their way.
	private var pinned: Set<PinTarget> = []

	private init() {}

	func isPinned(_ target: PinTarget) -> Bool {
		self.pinned.contains(target)
	}

	/// Re-reads the list. A failure (offline, signed out) keeps what is already shown.
	func refresh(server: NafynServer?) async {
		guard let server, let fetched = try? await server.send(Pins.list) as [PinnedItem] else { return }
		self.items = fetched.sorted { $0.pinnedAt > $1.pinnedAt }
		self.pinned = Set(fetched.map { PinTarget(kind: $0.kind, refId: $0.refId) })
	}

	/// Forgets everything, e.g. when signing out.
	func reset() {
		self.items = []
		self.pinned = []
	}

	/// Pins or unpins every target (idempotent on the server), then re-reads the list. Throws the first failure
	/// after rolling the local state back to what the server says.
	func setPinned(_ isPinned: Bool, _ targets: [PinTarget], server: NafynServer?) async throws {
		guard let server else { throw NafynError.unauthenticated }
		guard !targets.isEmpty else { return }

		if isPinned {
			self.pinned.formUnion(targets)
		} else {
			self.pinned.subtract(targets)
			self.items.removeAll { item in targets.contains(PinTarget(kind: item.kind, refId: item.refId)) }
		}

		do {
			try await withThrowingTaskGroup(of: Void.self) { group in
				for target in targets {
					group.addTask {
						if isPinned {
							_ = try await server.send(Pins.pin(kind: target.kind, refId: target.refId)) as PinResponse
						} else {
							_ = try await server.send(Pins.unpin(kind: target.kind, refId: target.refId)) as PinResponse
						}
					}
				}
				try await group.waitForAll()
			}
		} catch {
			await self.refresh(server: server)
			throw error
		}

		await self.refresh(server: server)
	}

	/// One target, with the failure shown in the app-wide toast: what the menu items use.
	func toggle(_ target: PinTarget, server: NafynServer?) {
		let wasPinned = self.isPinned(target)
		Task { @MainActor in
			do {
				try await self.setPinned(!wasPinned, [target], server: server)
				ToastState.app.success(wasPinned ? String(localized: "unpinned") : String(localized: "pinned-toast"))
			} catch {
				ToastState.app.failure(error)
			}
		}
	}
}

extension ToastState {
	/// The toast for actions that have no screen of their own to show one (context menu items). Mounted once, at
	/// the root of the app.
	static let app = ToastState()
}

/// "Pin" / "Unpin" for a menu: a `Menu` item, a `contextMenu` item or a toolbar button.
struct PinMenuButton: View {
	@Environment(\.server) private var server: NafynServer?

	let target: PinTarget

	var body: some View {
		let isPinned = PinStore.shared.isPinned(self.target)

		Button {
			PinStore.shared.toggle(self.target, server: self.server)
		} label: {
			Label(isPinned ? String(localized: "unpin") : String(localized: "pin"), systemImage: isPinned ? "pin.slash" : "pin")
		}
		.tint(Color.primary)
		.disabled(NetworkMonitor.shared.isOffline)
	}
}
