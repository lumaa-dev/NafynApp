// Made by Lumaa

import SwiftUI
import Safyn

struct SearchView: View {
	@Environment(\.server) private var server: NafynServer?
	@FocusState private var isSearchFocused: Bool

	@State private var query: String = ""
	@State private var filter: SearchFilter = .all
	@State private var result: SearchResult? = nil
	@State private var isSearching = false
	@State private var searchTask: Task<Void, Never>? = nil

	private let albumColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

	var body: some View {
		NavigationStack(path: Binding(get: { Navigator.shared.currentPath[Navigator.Tabs.search] ?? [] }, set: { Navigator.shared.currentPath[Navigator.Tabs.search] = $0 })) {
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
							SkeletonMusicGrid(columns: self.albumColumns, count: 2)

							VStack(spacing: 12) {
								SkeletonTrackRows(count: 4)
							}
						}
					} else if let result {
						if !result.albums.isEmpty {
							self.section(title: "albums") {
								LazyVGrid(columns: self.albumColumns, alignment: .leading, spacing: 16) {
									ForEach(result.albums, id: \.id) { info in
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

						if !result.tracks.isEmpty {
							self.section(title: "tracks") {
								LazyVStack(spacing: 12) {
									ForEach(result.tracks, id: \.id) { info in
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
			.background(DTColor.background.ignoresSafeArea())
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "search"))
		}
		.searchable(text: self.$query, prompt: String(localized: "search"))
		.searchFocused(self.$isSearchFocused)
		.onAppear {
			// Deferred a tick so the tab-switch transition and `.searchable`'s first-ever mount (which
			// pulls in UISearchController + keyboard resources) don't land in the same frame as the
			// keyboard-presentation work — stacking both was showing up as a dropped-framerate stall.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
				self.isSearchFocused = true
			}
		}
		.onSubmit(of: .search) {
			self.triggerSearch()
		}
		.onChange(of: self.filter) { _, _ in
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
			return
		}

		self.isSearching = true
		defer { self.isSearching = false }

		do {
			let result: SearchResult = try await server.send(Search.search(q: self.query, filter: self.filter == .all ? nil : self.filter))
			guard !Task.isCancelled else { return }
			self.result = result
		} catch {
			guard !Task.isCancelled else { return }
			self.result = nil
		}
	}
}
