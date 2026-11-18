// Made by Lumaa

import SwiftUI
import Safyn

/// The Discover tab: rows of mixes, suggestions, albums and playlists, ranked by the server's contextual
/// bandit (`Recommendations.home`). Every load is a new ranking decision; what the person opens, plays,
/// previews or requests from a card goes back to it through ``RecommendationFeedback``.
///
/// DESIGN.md has no section for this screen: it is built from the category grid (one horizontally scrolling
/// row per category on iOS), `MusicCard` and the Library tab's layout.
struct DiscoverView: View {
	@Environment(\.server) private var server: NafynServer?

	private enum Phase {
		case loading
		case loaded(RecommendationHome)
		/// The person turned personalization off (403).
		case off
		/// The server has the recommender switched off (404).
		case unavailable
		case failed(Error)
	}

	@State private var phase: Phase = .loading
	@State private var loadedAt: Date? = nil

	var body: some View {
		NavigationStack(path: Navigator.shared.path(for: .home)) {
			ScrollView {
				self.content
					.padding(.vertical)
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.contentColumn(maxWidth: DTLayout.gridWidth)
			.background(DTColor.background.ignoresSafeArea())
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "discover"))
			.toolbarTitleDisplayMode(.inlineLarge)
			.refreshable { await self.load() }
			.task {
				// coming back from a mix or an album is not a new visit: a page older than 10 minutes is
				if let loadedAt, Date.now.timeIntervalSince(loadedAt) < 600 { return }
				await self.load()
			}
		}
	}

	private func load() async {
		guard let server else { return }
		do {
			let home: RecommendationHome = try await server.send(Recommendations.home(device: .ios, tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60))
			self.phase = .loaded(home)
			self.loadedAt = .now
		} catch NafynError.server(let status, _) where status == 403 {
			self.phase = .off
		} catch NafynError.server(let status, _) where status == 404 {
			self.phase = .unavailable
		} catch {
			self.phase = .failed(error)
		}
	}

	@ViewBuilder
	private var content: some View {
		switch self.phase {
			case .loading:
				ProgressView()
					.tint(DTColor.textPrimary)
					.frame(maxWidth: .infinity)
					.padding(.top, 60)
			case .loaded(let home):
				if home.shelves.isEmpty {
					self.note(home.refreshing ? String(localized: "discover-building-first") : String(localized: "discover-empty"))
				} else {
					VStack(alignment: .leading, spacing: 28) {
						if home.refreshing {
							Text(String(localized: "discover-building"))
								.font(DTFont.system(14))
								.foregroundStyle(DTColor.textPrimary.opacity(0.7))
								.padding(.horizontal)
						}
						ForEach(home.shelves) { shelf in
							self.shelfView(shelf)
						}
					}
				}
			case .off:
				VStack(alignment: .leading, spacing: 12) {
					self.note(String(localized: "discover-off"))
					Button(String(localized: "privacy")) {
						Navigator.shared.send(to: .settingsPrivacy)
					}
					.buttonStyle(.hollow())
					.padding(.horizontal)
				}
			case .unavailable:
				self.note(String(localized: "discover-unavailable"))
			case .failed(let error):
				// DESIGN.md "Error messages": where the screen should have changed, in the secondary colour
				self.note(error.localizedDescription)
		}
	}

	private func note(_ text: String) -> some View {
		Text(text)
			.font(DTFont.system(15))
			.foregroundStyle(DTColor.textPrimary.opacity(0.7))
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)
	}

	/// A category grid: one row on iOS, scrolling sideways inside its own frame.
	private func shelfView(_ shelf: RecommendationShelf) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(shelf.kind.title)
				.font(DTFont.serifItalic(25))
				.foregroundStyle(DTColor.textPrimary)
				.padding(.horizontal)

			ScrollView(.horizontal, showsIndicators: false) {
				LazyHStack(alignment: .top, spacing: 14) {
					ForEach(shelf.cards) { card in
						self.cardView(card, shelf: shelf)
							.frame(width: 150)
					}
				}
				.padding(.horizontal)
			}
			.scrollClipDisabled()
		}
	}

	@ViewBuilder
	private func cardView(_ card: RecommendationCard, shelf: RecommendationShelf) -> some View {
		let item = card.item
		let why = card.explanation.text
		switch item.kind {
			case .album, .playlist, .track:
				// the same card (and menu) as the recently-played shelf for an owned album or a playlist
				let entry = RecentlyPlayedEntry(
					type: item.kind == .album ? .album : item.kind == .playlist ? .playlist : .track,
					refId: item.refId,
					playedAt: 0,
					title: item.title,
					subtitle: item.subtitle,
					coverArt: item.coverArt,
					playlistImage: item.playlistImage,
					href: item.href,
					coverMediaId: item.coverMediaId
				)
				let musicEntry = MusicCardEntry.recentlyPlayed(entry)
				Button {
					RecommendationFeedback.shared.cardOpened(decisionId: shelf.decisionId, slot: card.slot, item: item, server: self.server)
					if let destination = musicEntry.destination { Navigator.shared.send(to: destination) }
				} label: {
					MusicCard(musicEntry, subtitle: [item.subtitle, why].compactMap { $0 }.joined(separator: " · "))
				}
				.buttonStyle(.plain)
			case .mix, .suggestion:
				Button {
					RecommendationFeedback.shared.cardOpened(decisionId: shelf.decisionId, slot: card.slot, item: item, server: self.server)
					Navigator.shared.send(to: item.kind == .mix ? .mix(id: item.refId) : .track(id: item.refId))
				} label: {
					RecommendationCardLabel(item: item, explanation: why)
				}
				.buttonStyle(.plain)
			case .unknown:
				EmptyView()
		}
	}
}

/// A mix or a catalogue suggestion, laid out like a `MusicCard` highlight.
private struct RecommendationCardLabel: View {
	let item: RecommendationItem
	let explanation: String?

	private var title: String {
		self.item.label?.localizedTitle ?? self.item.title
	}

	var body: some View {
		VStack(alignment: .leading) {
			if self.item.kind == .mix {
				MixCover(covers: self.item.covers ?? [])
			} else {
				Color.clear
					.aspectRatio(1.0, contentMode: .fit)
					.overlay {
						CoverImage(url: self.item.coverArt.flatMap { $0.contains("/art/") ? $0.coverArtURL(size: 500) : URL(string: $0) }, cornerRadius: 0)
					}
					.clipShape(RoundedRectangle(cornerRadius: 10))
			}

			Text(self.title)
				.font(DTFont.serif(18))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)

			if let subtitle = self.item.subtitle {
				Text(subtitle)
					.font(DTFont.serif(16))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}

			if let explanation {
				Text(explanation)
					.font(DTFont.serifItalic(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.75))
					.lineLimit(2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10))
		.hoverEffect()
		.accessibilityElement(children: .combine)
	}
}
