// Made by Lumaa

import SwiftUI
import Charts
import Safyn

/// "Your Music Year" — the year-in-review screen built on `Insights.yearly(year:)`.
///
/// Everything on screen comes from that one response (totals, per-month minutes, hour histogram, and
/// the top-5 of each entity kind), so the whole screen is a single `AsyncContentView` fetch; the
/// "see all" lists, the Replay Mix, the reel, and the year comparison are separate screens.
struct MusicYearView: View {
	@Environment(\.server) private var server: NafynServer?

	/// The year to show, or `nil` for the server's default (the current year).
	let year: Int?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Insights.yearly(year: self.year)) as YearlyInsights
		} content: { insights, reload in
			MusicYearContent(insights: insights, reload: reload)
		}
		.navigationTitle(String(localized: "music-year"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct MusicYearContent: View {
	@Environment(\.server) private var server: NafynServer?

	let insights: YearlyInsights
	let reload: () async -> Void

	@State private var showingReel = false
	@State private var shareImage: Image? = nil
	@State private var isPreparingShare = false
	@State private var toast = ToastState()

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				self.header

				if self.insights.gate.enough {
					self.totals
					self.actions
					self.monthlyChart
					self.hourChart
					self.rankings
				} else {
					InsightsGateView(gate: self.insights.gate)
				}
			}
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.toast(self.toast)
		.fullScreenCover(isPresented: self.$showingReel) {
			HighlightReelView(year: self.insights.year)
				.environment(\.server, self.server)
		}
		.toolbar {
			if self.insights.availableYears.count > 1 {
				ToolbarItem(placement: .primaryAction) {
					Menu {
						ForEach(self.insights.availableYears, id: \.self) { year in
							Button {
								guard year != self.insights.year else { return }
								Navigator.shared.send(to: .musicYear(year: year))
							} label: {
								if year == self.insights.year {
									Label(String(year), systemImage: "checkmark")
								} else {
									Text(String(year))
								}
							}
						}
					} label: {
						Image(systemName: "calendar")
					}
					.tint(Color.primary)
				}
			}
		}
	}

	// MARK: - Header

	@ContentBuilder
	private var header: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(String(self.insights.year))
				.font(DTFont.serif(60))
				.foregroundStyle(DTColor.textPrimary)

			Text(String(localized: "music-year-subtitle"))
				.font(DTFont.system(15))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			if self.insights.snapshot {
				Label(String(localized: "insights-snapshot"), systemImage: "lock")
					.font(DTFont.system(12))
					.foregroundStyle(DTColor.textPrimary.opacity(0.45))
					.padding(.top, 2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	// MARK: - Totals

	@ContentBuilder
	private var totals: some View {
		let totals = self.insights.totals

		LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
			InsightsStatTile(
				value: InsightsFormat.minutes(totals.totalMinutes),
				caption: String(localized: "insights-total-listening")
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.totalPlays),
				caption: String(localized: "insights-total-plays")
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.uniqueTracks),
				caption: String(localized: "insights-unique-tracks")
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.uniqueArtists),
				caption: String(localized: "insights-unique-artists")
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.uniqueAlbums),
				caption: String(localized: "insights-unique-albums")
			)

			if let streak = totals.longestStreakDays {
				InsightsStatTile(
					value: String(localized: "\(streak)-days"),
					caption: String(localized: "insights-longest-streak")
				)
			}
		}
	}

	// MARK: - Actions

	@ContentBuilder
	private var actions: some View {
		VStack(spacing: 10) {
			Button {
				self.showingReel = true
			} label: {
				Label(String(localized: "insights-play-reel"), systemImage: "play.rectangle")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())

			HStack(spacing: 10) {
				Button {
					Navigator.shared.send(to: .replayMix(year: String(self.insights.year)))
				} label: {
					Label(String(localized: "replay-mix"), systemImage: "music.note.list")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())

				Button {
					Navigator.shared.send(to: .yearComparison)
				} label: {
					Label(String(localized: "insights-compare"), systemImage: "chart.line.uptrend.xyaxis")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())
			}

			if let shareImage {
				ShareLink(
					item: shareImage,
					preview: SharePreview(String(localized: "music-year"), image: shareImage)
				) {
					Label(String(localized: "insights-share"), systemImage: "square.and.arrow.up")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())
			} else {
				Button {
					self.prepareShareImage()
				} label: {
					if self.isPreparingShare {
						ProgressView()
							.frame(maxWidth: .infinity)
					} else {
						Label(String(localized: "insights-share"), systemImage: "square.and.arrow.up")
							.frame(maxWidth: .infinity)
					}
				}
				.buttonStyle(.hollow())
				.disabled(self.isPreparingShare)
			}
		}
	}

	// MARK: - Charts

	@ContentBuilder
	private var monthlyChart: some View {
		if self.insights.monthlyMinutes.contains(where: { $0 > 0 }) {
			VStack(alignment: .leading, spacing: 12) {
				InsightsSectionHeader(String(localized: "insights-by-month"))

				Chart(Array(self.insights.monthlyMinutes.enumerated()), id: \.offset) { index, minutes in
					BarMark(
						x: .value(String(localized: "month"), InsightsFormat.monthInitial(index + 1)),
						y: .value(String(localized: "minutes"), minutes)
					)
					.foregroundStyle(DTColor.accentGradient)
					.cornerRadius(6)
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.frame(height: 180)
			}
		}
	}

	@ContentBuilder
	private var hourChart: some View {
		if self.insights.hourHistogram.contains(where: { $0.minutes > 0 }) {
			VStack(alignment: .leading, spacing: 12) {
				InsightsSectionHeader(String(localized: "insights-by-hour"))

				Chart(self.insights.hourHistogram, id: \.hour) { point in
					BarMark(
						x: .value(String(localized: "hour"), point.hour),
						y: .value(String(localized: "minutes"), point.minutes)
					)
					.foregroundStyle(DTColor.accentGradient)
					.cornerRadius(3)
				}
				.chartXAxis {
					AxisMarks(values: [0, 6, 12, 18, 23]) { value in
						AxisValueLabel {
							if let hour = value.as(Int.self) {
								Text(InsightsFormat.hourLabel(hour))
							}
						}
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.frame(height: 150)

				if let peak = self.insights.hourHistogram.max(by: { $0.minutes < $1.minutes }), peak.minutes > 0 {
					Text(String(localized: "insights-peak-hour-\(InsightsFormat.hourLabel(peak.hour))"))
						.font(DTFont.system(13))
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				}
			}
		}
	}

	// MARK: - Rankings

	@ContentBuilder
	private var rankings: some View {
		self.ranking(String(localized: "top-tracks"), entities: self.insights.top.track, kind: .track)
		self.ranking(String(localized: "top-artists"), entities: self.insights.top.artist, kind: .artist)
		self.ranking(String(localized: "top-albums"), entities: self.insights.top.album, kind: .album)
		self.ranking(String(localized: "top-playlists"), entities: self.insights.top.playlist, kind: .playlist)
	}

	@ContentBuilder
	private func ranking(_ title: String, entities: [RankedEntity]?, kind: RankedEntityKind) -> some View {
		if let entities, !entities.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				InsightsSectionHeader(title: title) {
					Button(String(localized: "see-all")) {
						Navigator.shared.send(to: .insightsTop(type: kind, period: "year", year: self.insights.year, month: nil))
					}
					.font(DTFont.system(14))
					.tint(Color.primary)
				}

				ForEach(entities.prefix(5)) { entity in
					RankedEntityRow(entity: entity) {
						entity.navigate()
					}
				}
			}
		}
	}

	// MARK: - Sharing

	/// Renders the share card off-screen into an `Image`, which `ShareLink` can then hand to the share
	/// sheet. Rendering is deferred until the user asks for it — the card pulls the top tracks' artwork
	/// over the network, which isn't worth doing for everyone who merely opens the screen.
	private func prepareShareImage() {
		self.isPreparingShare = true

		Task {
			let covers = await MusicYearShareCard.loadCovers(for: self.insights)
			let card = MusicYearShareCard(insights: self.insights, covers: covers)

			await MainActor.run {
				let renderer = ImageRenderer(content: card)
				renderer.scale = 3

				#if canImport(UIKit)
				if let uiImage = renderer.uiImage {
					self.shareImage = Image(uiImage: uiImage)
				} else {
					self.toast.failure(NafynError.invalidResponse)
				}
				#endif

				self.isPreparingShare = false
			}
		}
	}
}

extension RankedEntity {
	/// Pushes the detail screen for this ranked entity, when one exists for its kind.
	///
	/// `entityId` is already the ID each destination expects: a media ID for tracks, a release-group
	/// MusicBrainz ID for albums, an artist MusicBrainz ID for artists, and a playlist ID for playlists.
	/// Artists ranked by name rather than MBID have no detail screen to open, so they don't navigate.
	func navigate() {
		switch self.entityType {
			case .track:
				Navigator.shared.send(to: .libraryTrack(id: self.entityId))
			case .album:
				Navigator.shared.send(to: .album(id: self.entityId))
			case .artist:
				guard self.entityId.contains("-") else { return }
				Navigator.shared.send(to: .artist(id: self.entityId))
			case .playlist:
				Navigator.shared.send(to: .playlist(id: self.entityId))
		}
	}
}
