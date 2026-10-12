// Made by Lumaa

import SwiftUI
import Safyn

struct LibraryView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var recntPlays: [RecentlyPlayedEntry] = []

	private let colItems: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
		NavigationStack(path: Binding(get: { Navigator.shared.currentPath[Navigator.Tabs.library] ?? [] }, set: { Navigator.shared.currentPath[Navigator.Tabs.library] = $0 } )) {
			ScrollView {
				self.navItems
					.padding(.top)
					.padding(.horizontal)

				self.recents
					.padding(.horizontal)
					.padding(.vertical)
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.background(DTColor.background.ignoresSafeArea())
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "library"))
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button {
						Navigator.shared.send(to: .settings)
					} label: {
						Image(systemName: "gearshape")
					}
					.tint(Color.primary)
				}
			}
			.task {
				guard let server else { return }
				self.recntPlays = (try? await server.send(Library.recentlyPlayed)) ?? []
			}
		}
    }

	@ContentBuilder
	private var navItems: some View {
		HStack {
			self.navBtn(String(localized: "tracks"), systemImage: "music.note", path: .myTracks)

			self.navBtn(String(localized: "albums"), systemImage: "square.stack", path: .myAlbums)

			self.navBtn(String(localized: "playlists"), systemImage: "music.note.list", path: .myPlaylists)

			// Only once listening history is on — with it off there's nothing behind this screen but the
			// "keep listening" gate, and the setting is opt-in.
			if PlayTracker.shared.historyEnabled {
				self.navBtn(String(localized: "music-year"), systemImage: "sparkles", path: .musicYear(year: nil))
			}
		}
	}

	@ContentBuilder
	private var recents: some View {
		let entries = self.mergedRecents
		if !entries.isEmpty {
			LazyVStack(alignment: .leading) {
				Text("recently-played")
					.font(DTFont.serifItalic(25))

				LazyVGrid(columns: colItems, alignment: .leading) {
					ForEach(entries) { elm in
						NavigationLink(value: elm.destination) {
							MusicCard(elm.cardEntry)
								.frame(maxWidth: .infinity, alignment: .leading)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	/// `recntPlays` as-is while online. Downloaded tracks only get folded in while offline — online,
	/// server history is always reachable and authoritative, and downloads are just a local cache of
	/// tracks already represented there, so unconditionally merging them pushed every downloaded track
	/// to the top of the grid ahead of genuinely more-recent online plays.
	private var mergedRecents: [RecentGridEntry] {
		var result: [RecentGridEntry] = self.recntPlays.map { entry in
			RecentGridEntry(id: "recent-\(entry.refId)-\(entry.playedAt)", timestamp: entry.playedAtDate, cardEntry: .recentlyPlayed(entry), destination: entry.destination)
		}

		if NetworkMonitor.shared.isOffline {
			let seenTrackIds = Set(self.recntPlays.filter { $0.type == .track }.map(\.refId))
			for track in DownloadManager.shared.downloads where !seenTrackIds.contains(track.id) {
				result.append(RecentGridEntry(id: "download-\(track.id)", timestamp: track.downloadedAt, cardEntry: .media(track.mediaRow), destination: .libraryTrack(id: track.id)))
			}
		}

		return result.sorted { $0.timestamp > $1.timestamp }
	}

	private struct RecentGridEntry: Identifiable {
		let id: String
		let timestamp: Date
		let cardEntry: MusicCardEntry
		let destination: Navigator.Paths
	}

	@ContentBuilder
	private func navBtn(_ title: String, systemImage: String = "circle.fill", path: Navigator.Paths) -> some View {
		VStack(alignment: .center, spacing: 4) {
			Button {
				Navigator.shared.send(to: path)
			} label: {
				Image(systemName: systemImage)
					.resizable()
					.scaledToFit()
					.frame(width: 25, height: 25, alignment: .center)
					.padding(5.0)
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.tint(Color.primary)

			Text(title)
		}
		.frame(maxWidth: .infinity, alignment: .center)
	}
}

#Preview {
    LibraryView()
}
