// Made by Lumaa

import SwiftUI
import Safyn

/// Admin view: every media row across every user's library, with per-owner remove actions.
/// Requires `manageMusic` — reached only via a link from `SettingsView`'s Storage section, but the
/// server itself enforces the permission regardless of how this screen is reached.
struct AllLibraryView: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var paginator: Paginator<LibraryMediaEntry>? = nil
	@State private var toast = ToastState()

	var body: some View {
		Group {
			if let paginator {
				PaginatedList(paginator: paginator) { entry in
					self.row(entry)
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
			self.paginator = Paginator<LibraryMediaEntry> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/library/all", page: page, limit: limit)
			}
		}
		.navigationTitle(String(localized: "everyone-library"))
		.toast(self.toast)
	}

	@ViewBuilder
	private func row(_ entry: LibraryMediaEntry) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			TrackRow(title: entry.media.title, subtitle: entry.media.artistName, duration: entry.media.duration)

			HStack(spacing: 6) {
				ForEach(entry.owners, id: \.userId) { owner in
					Menu {
						Button(role: .destructive) {
							self.removeForUser(entry, owner: owner)
						} label: {
							Label(String(localized: "remove"), systemImage: "trash")
						}
					} label: {
						Text(owner.username)
							.font(DTFont.system(14))
							.foregroundStyle(DTColor.textPrimary.opacity(0.7))
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(DTColor.surfaceInput, in: Capsule())
					}
					.tint(Color.primary)
				}
			}
		}
		.padding(.vertical, 4)
	}

	private func removeForUser(_ entry: LibraryMediaEntry, owner: LibraryMediaEntry.Owner) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Library.removeForUser(id: entry.media.id, userId: owner.userId)) as RemovedWithFileResponse
				if entry.owners.count <= 1 {
					self.paginator?.remove(where: { $0.media.id == entry.media.id })
				} else {
					self.paginator?.update(id: entry.id) { item in
						item = LibraryMediaEntry(media: item.media, owners: item.owners.filter { $0.userId != owner.userId })
					}
				}
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
