// Made by Lumaa

import SwiftUI
import Safyn

/// A `List`-based infinite-scroll wrapper around a ``Paginator``: fetches the first page on appear,
/// loads more as the user nears the tail, and supports pull-to-refresh.
struct PaginatedList<Item: Codable & Sendable & Identifiable & Hashable, RowContent: View>: View {
	@State var paginator: Paginator<Item>

	@ViewBuilder let row: (Item) -> RowContent

	var body: some View {
		List {
			ForEach(self.paginator.items) { item in
				self.row(item)
					.listRowBackground(Color.clear)
					.onAppear { self.paginator.loadNextPageIfNeeded(currentItem: item) }
			}

			if self.paginator.isLoadingPage {
				SkeletonTrackRows(count: self.paginator.items.isEmpty ? 8 : 2)
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)
			}

			if let error = self.paginator.error, self.paginator.items.isEmpty {
				VStack(spacing: 12) {
					Text(error.localizedDescription)
						.font(DTFont.system(16))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
						.multilineTextAlignment(.center)

					Button(String(localized: "retry")) {
						Task { await self.paginator.reset() }
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
		.task {
			guard self.paginator.items.isEmpty else { return }
			await self.paginator.reset()
		}
		.refreshable {
			await self.paginator.reset()
		}
	}
}
