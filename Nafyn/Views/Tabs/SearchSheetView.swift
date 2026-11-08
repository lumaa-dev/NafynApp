// Made by Lumaa

import SwiftUI
import Safyn

/// ``SearchView`` for a sheet: same results, but with its own navigation stack (a sheet must not push onto
/// the Search tab's stack behind it), a close button, a query that can be pre-filled, and the search field in
/// the bottom toolbar so it stays within reach on a tall phone and off the hinge on the iPhone Duo.
struct SearchSheetView: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	@State private var query: String
	@State private var path: [Navigator.Paths] = []
	@State private var filter: SearchFilter = .all
	@State private var result: SearchResult? = nil
	@State private var isSearching = false
	@State private var searchTask: Task<Void, Never>? = nil
	/// Which search is the latest; see ``search()``.
	@State private var searchGeneration = 0
	/// Whether the first (pre-filled) search already ran; later edits are debounced, that one is not.
	@State private var hasStarted = false

	/// - Parameter query: Search run as soon as the sheet appears; empty waits for the user.
	init(query: String = String()) {
		self._query = State(initialValue: query)
	}

	var body: some View {
		NavigationStack(path: self.$path) {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					Picker(String(localized: "filter"), selection: self.$filter) {
						Text("all").tag(SearchFilter.all)
						Text("albums").tag(SearchFilter.album)
						Text("artists").tag(SearchFilter.artist)
						Text("tracks").tag(SearchFilter.track)
					}
					.pickerStyle(.segmented)

					if self.isSearching {
						VStack(spacing: 12) {
							SkeletonTrackRows(count: 8)
						}
					} else if let result {
						// ONE list, the most likely result on top (DESIGN.md "Search"); the filter above keeps only one kind
						SearchResultsList(result: result)
					}
				}
				.padding()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.contentColumn(maxWidth: DTLayout.gridWidth)
			.background(DTColor.background.ignoresSafeArea())
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "search"))
			.navigationBarTitleDisplayMode(.inline)
			// Must sit inside the stack: outside it, the bottom-bar search item has no field to show or submit.
			.searchable(text: self.$query, prompt: String(localized: "search"))
			.searchToolbarBehavior(.minimize)
			.onSubmit(of: .search) {
				self.triggerSearch()
			}
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "close"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}

				// The search field lives in the bottom bar instead of under the title.
				DefaultToolbarItem(kind: .search, placement: .bottomBar)
			}
		}
		.sheetBackground()
		.onChange(of: self.filter) { _, _ in
			self.triggerSearch()
		}
		// Searches as the user types (debounced), and right away for a pre-filled query: `id` re-runs the task
		// on every edit and cancels the previous one, so its sleep is the debounce.
		.task(id: self.query) {
			if self.hasStarted {
				try? await Task.sleep(for: .milliseconds(400))
				guard !Task.isCancelled else { return }
			}
			self.hasStarted = true
			self.triggerSearch()
		}
	}

	private func triggerSearch() {
		self.searchTask?.cancel()
		self.searchTask = Task {
			await self.search()
		}
	}

	private func search() async {
		// only the latest search may touch the state: a cancelled one ends after its replacement started
		self.searchGeneration += 1
		let generation = self.searchGeneration

		guard let server, !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			self.result = nil
			self.isSearching = false
			return
		}

		self.isSearching = true

		do {
			let result: SearchResult = try await server.send(Search.search(q: self.query, filter: self.filter == .all ? nil : self.filter))
			guard generation == self.searchGeneration, !Task.isCancelled else { return }
			self.result = result
			self.isSearching = false
		} catch {
			guard generation == self.searchGeneration, !Task.isCancelled else { return }
			self.result = nil
			self.isSearching = false
		}
	}
}
