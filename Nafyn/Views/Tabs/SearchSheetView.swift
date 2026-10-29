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
	/// The server's single top-ranked album/track (`MediaInfo.bestResult`), cached so `body` doesn't rescan.
	@State private var bestResult: MediaInfo? = nil
	@State private var isSearching = false
	@State private var searchTask: Task<Void, Never>? = nil
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
						VStack(alignment: .leading, spacing: 20) {
							SkeletonMusicGrid(count: 2)

							VStack(spacing: 12) {
								SkeletonTrackRows(count: 4)
							}
						}
					} else if let result {
						if let best = self.bestResult {
							self.section(title: "best-result") {
								self.row(.info(best))
							}
							.padding()
							.background(Material.ultraThin)
							.clipShape(RoundedRectangle(cornerRadius: 15.0))
						}

						if result.albums.contains(where: { $0.id != self.bestResult?.id }) {
							self.section(title: "albums") {
								FoldGrid(alignment: .leading, spacing: 16) {
									ForEach(result.albums.filter { $0.id != self.bestResult?.id }, id: \.id) { info in
										self.card(.info(info))
									}
								}
							}
						}

						if !result.artists.isEmpty {
							self.section(title: "artists") {
								LazyVStack(spacing: 12) {
									ForEach(result.artists, id: \.musicbrainzId) { artist in
										self.row(.artist(artist))
									}
								}
							}
						}

						if result.tracks.contains(where: { $0.id != self.bestResult?.id }) {
							self.section(title: "tracks") {
								LazyVStack(spacing: 12) {
									ForEach(result.tracks.filter { $0.id != self.bestResult?.id }, id: \.id) { info in
										self.row(.info(info))
									}
								}
							}
						}

						if result.albums.isEmpty && result.artists.isEmpty && result.tracks.isEmpty {
							Text("no-results")
								.font(DTFont.system(18))
								.foregroundStyle(DTColor.textPrimary.opacity(0.5))
								.frame(maxWidth: .infinity)
								.padding(.top, 40)
						}
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

	@ViewBuilder
	private func section<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.title2.bold())

			content()
		}
	}

	@ViewBuilder
	private func card(_ entry: MusicCardEntry) -> some View {
		if let destination = entry.destination {
			NavigationLink(value: destination) {
				MusicCard(entry)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)
		} else {
			MusicCard(entry)
		}
	}

	@ViewBuilder
	private func row(_ entry: MusicCardEntry) -> some View {
		if let destination = entry.destination {
			NavigationLink(value: destination) {
				MusicCard(entry, type: .row)
			}
			.buttonStyle(.plain)
		} else {
			MusicCard(entry, type: .row)
		}
	}

	private func triggerSearch() {
		self.searchTask?.cancel()
		self.searchTask = Task {
			await self.search()
		}
	}

	private func search() async {
		guard let server, !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			self.result = nil
			self.bestResult = nil
			return
		}

		self.isSearching = true
		defer { self.isSearching = false }

		do {
			let result: SearchResult = try await server.send(Search.search(q: self.query, filter: self.filter == .all ? nil : self.filter))
			guard !Task.isCancelled else { return }
			self.result = result
			self.bestResult = (result.albums + result.tracks).first { $0.bestResult == true }
		} catch {
			guard !Task.isCancelled else { return }
			self.result = nil
			self.bestResult = nil
		}
	}
}
