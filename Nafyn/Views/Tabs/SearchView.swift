// Made by Lumaa

import SwiftUI
import Safyn

struct SearchView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var query: String = ""
	@State private var filter: SearchFilter = .all
	@State private var result: SearchResult? = nil
	@State private var isSearching = false
	@State private var searchTask: Task<Void, Never>? = nil
	/// Which search is the latest; see ``search()``.
	@State private var searchGeneration = 0

	var body: some View {
		NavigationStack(path: Navigator.shared.path(for: .search)) {
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
		}
		.searchable(text: self.$query, prompt: String(localized: "search"))
		.onSubmit(of: .search) {
			self.triggerSearch()
		}
		.onChange(of: self.filter) { _, _ in
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
		// Only the latest search may touch the state. A cancelled one finishes later than its replacement
		// starts: letting it clear `isSearching` made the skeleton vanish (and the old results or nothing show)
		// while the new search was still running, the glitch of changing the filter before results are in.
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
