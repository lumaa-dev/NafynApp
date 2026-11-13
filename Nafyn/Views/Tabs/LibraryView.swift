// Made by Lumaa

import SwiftUI
import Safyn

struct LibraryView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var recntPlays: [RecentlyPlayedEntry] = []
	/// The signed-in user, for the picture of the profile button; `nil` until fetched (or offline).
	@State private var me: NafynUser? = nil

    var body: some View {
		NavigationStack(path: Navigator.shared.path(for: .library)) {
			ScrollView {
				self.pins
					.padding(.top)
					.padding(.horizontal)

				self.navItems
					.padding(.top)
					.padding(.horizontal)

				self.recents
					.padding(.horizontal)
					.padding(.vertical)
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.contentColumn(maxWidth: DTLayout.gridWidth)
			.background(DTColor.background.ignoresSafeArea())
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "library"))
			.toolbarTitleDisplayMode(.inlineLarge)
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button {
						Navigator.shared.send(to: .userProfile)
					} label: {
						ProfileAvatarLabel(url: self.me.flatMap { self.server?.avatarURL(userId: $0.id, version: $0.avatar) })
					}
					.tint(Color.primary)
				}

				// the profile and the settings have nothing to do with one another
				ToolbarSpacer(.fixed, placement: .primaryAction)

				ToolbarItem(placement: .primaryAction) {
					Button {
						Navigator.shared.send(to: .settings)
					} label: {
						// title + symbol: the vertical toolbar on the Duo's outer display drops icon-only items
						Label(String(localized: "settings"), systemImage: "gearshape")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
			.task {
				await PinStore.shared.refresh(server: self.server)
			}
			.task {
				// once: the task runs again every time the library re-appears (coming back from My Tracks...)
				guard self.me == nil, let server else { return }
				self.me = try? await server.send(User.me) as NafynUser
			}
			.task {
				guard let server else { return }
				self.recntPlays = (try? await server.send(Library.recentlyPlayed)) ?? []
			}
		}
    }

	/// The user's pins, newest first, in three columns. Absent until something is pinned.
	@ContentBuilder
	private var pins: some View {
		let pinned = PinStore.shared.items
		if !pinned.isEmpty {
			VStack(alignment: .leading) {
				Text("pinned")
					.font(DTFont.serifItalic(25))

				FoldGrid(alignment: .leading, spacing: 12, columns: 3) {
					ForEach(pinned, id: \.self) { pin in
						let entry = MusicCardEntry.pinned(pin)
						if let destination = entry.destination {
							NavigationLink(value: destination) {
								MusicCard(entry)
									.frame(maxWidth: .infinity, alignment: .leading)
							}
							.buttonStyle(.plain)
						}
					}
				}
				// three columns would blow the covers up in a wide window
				.frame(maxWidth: 3 * 180 + 2 * 12, alignment: .leading)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
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

				FoldGrid(alignment: .leading) {
					ForEach(entries) { elm in
						NavigationLink(value: elm.destination) {
							MusicCard(elm.cardEntry, onRemoved: { self.forget(elm.cardEntry) })
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

	/// A deleted album/track must leave the grid, with every play of it.
	private func forget(_ entry: MusicCardEntry) {
		guard case .recentlyPlayed(let removed) = entry else { return }
		self.recntPlays.removeAll { $0.refId == removed.refId && $0.type == removed.type }
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
