// Made by Lumaa

import SwiftUI
import Safyn

/// Generic infinite-scroll pagination state for any Safyn endpoint that returns a ``PaginatedResponse``.
@Observable
final class Paginator<Item: Codable & Sendable & Identifiable & Hashable> {
	private(set) var items: [Item] = []
	private(set) var isLoadingPage = false
	private(set) var hasMore = true
	private(set) var error: Error? = nil

	private var currentPage = 0
	private let pageSize: Int
	private let fetchPage: (_ page: Int, _ limit: Int) async throws -> PaginatedResponse<Item>

	init(pageSize: Int = 50, seed: PaginatedResponse<Item>? = nil, fetchPage: @escaping (Int, Int) async throws -> PaginatedResponse<Item>) {
		self.pageSize = pageSize
		self.fetchPage = fetchPage

		if let seed {
			self.items = seed.items
			self.currentPage = seed.page
			self.hasMore = seed.hasMore
		}
	}

	/// Loads the first page, replacing any existing items. Call from `.task`/`.refreshable`.
	func reset() async {
		self.currentPage = 0
		self.items = []
		self.hasMore = true
		self.error = nil
		await self.loadMore()
	}

	/// Loads the next page, appending to `items`. No-op while already loading or once `hasMore` is `false`.
	func loadMore() async {
		guard !self.isLoadingPage, self.hasMore else { return }

		self.isLoadingPage = true
		defer { self.isLoadingPage = false }

		let nextPage = self.currentPage + 1
		do {
			let page = try await self.fetchPage(nextPage, self.pageSize)
			self.items.append(contentsOf: page.items)
			self.currentPage = page.page
			self.hasMore = page.hasMore
			self.error = nil
		} catch {
			self.error = error
		}
	}

	/// Removes items matching `predicate` from the already-loaded list, e.g. after a successful delete.
	func remove(where predicate: (Item) -> Bool) {
		self.items.removeAll(where: predicate)
	}

	/// Inserts a freshly created item at the front of the already-loaded list.
	func prepend(_ item: Item) {
		self.items.insert(item, at: 0)
	}

	/// Mutates the already-loaded item with the given `id` in place, e.g. after a partial update.
	func update(id: Item.ID, transform: (inout Item) -> Void) {
		guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
		transform(&self.items[index])
	}

	/// Reorders the already-loaded list in place, e.g. for drag-to-reorder — the caller is responsible
	/// for persisting the new order server-side.
	func move(fromOffsets: IndexSet, toOffset: Int) {
		self.items.move(fromOffsets: fromOffsets, toOffset: toOffset)
	}

	/// Call from a row's `.onAppear` — triggers `loadMore()` once the visible item is near the tail.
	func loadNextPageIfNeeded(currentItem: Item) {
		guard let index = self.items.firstIndex(where: { $0.id == currentItem.id }) else { return }
		let thresholdIndex = self.items.index(self.items.endIndex, offsetBy: -5, limitedBy: self.items.startIndex) ?? self.items.startIndex
		guard index >= thresholdIndex else { return }

		Task { await self.loadMore() }
	}
}
