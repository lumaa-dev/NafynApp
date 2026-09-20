// Made by Lumaa

import SwiftUI
import Charts
import Safyn

/// The period an ``InsightsView`` is currently showing: either a `YYYY-MM` month or a four-digit year.
enum InsightsPeriod: Hashable {
	case month(String)
	case year(Int)
}

/// The unified "Wrapped"-style recap screen: hosts both the monthly and yearly summaries and swaps
/// between them in place as the picker below is used, instead of pushing a new screen per period (which
/// used to grow the tab's nav stack on every tap — see `Navigator`).
///
/// `Navigator.Paths.musicYear(year:)`/`.monthlyInsights(month:)` stay as deep-link entry points; they
/// each construct this view with the right starting ``InsightsPeriod`` (see `MusicYearView`/
/// `MonthlyInsightsView`, now thin wrappers around this view).
struct InsightsView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var period: InsightsPeriod
	/// The year whose 12 months populate the picker row. Independent of `period` — changing it only
	/// repopulates the row (and the trailing year-pill's target), it doesn't change what's displayed
	/// below until a pill is actually tapped.
	@State private var browsingYear: Int

	@State private var yearly: YearlyInsights?
	@State private var monthly: MonthlyInsights?
	@State private var availableYears: [Int] = []
	@State private var isLoading = false
	@State private var loadError: Error?

	@State private var showingReel = false
	@State private var shareImage: Image? = nil
	@State private var isPreparingShare = false
	@State private var toast = ToastState()

	init(initialPeriod: InsightsPeriod) {
		self._period = State(initialValue: initialPeriod)
		switch initialPeriod {
			case .month(let month):
				self._browsingYear = State(initialValue: Self.year(of: month))
			case .year(let year):
				self._browsingYear = State(initialValue: year)
		}
	}

	private static func year(of monthIdentifier: String) -> Int {
		Int(monthIdentifier.split(separator: "-").first ?? "") ?? Calendar.current.component(.year, from: .now)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				self.periodPicker

				Group {
					if let yearly = self.yearly, case .year = self.period {
						YearInsightsBody(insights: yearly, showingReel: self.$showingReel)
					} else if let monthly = self.monthly, case .month = self.period {
						MonthInsightsBody(insights: monthly)
					} else if let loadError {
						self.errorView(loadError)
					} else {
						SkeletonDetailScreen()
					}
				}
				.opacity(self.isLoading && (self.yearly != nil || self.monthly != nil) ? 0.4 : 1)
				.overlay {
					if self.isLoading && (self.yearly != nil || self.monthly != nil) {
						ProgressView()
							.tint(DTColor.textPrimary)
					}
				}
				.animation(DTMotion.sidebar, value: self.isLoading)

				self.shareAction
			}
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.toast(self.toast)
		.navigationTitle(String(localized: "music-year"))
		.navigationBarTitleDisplayMode(.inline)
		.fullScreenCover(isPresented: self.$showingReel) {
			if case .year(let year) = self.period {
				HighlightReelView(year: year)
					.environment(\.server, self.server)
			}
		}
		.task {
			// One-time metadata fetch, independent of the currently-displayed period: `MonthlyInsights`
			// carries no `availableYears`, only `YearlyInsights` does, so the year-switcher menu needs
			// this even while browsing a month.
			guard self.availableYears.isEmpty, let server else { return }
			guard let insights = try? await server.send(Insights.yearly(year: nil)) as YearlyInsights else { return }
			self.availableYears = insights.availableYears
			if case .year(let year) = self.period, year == insights.year {
				self.yearly = insights
			}
		}
		.task(id: self.period) {
			await self.load()
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Menu {
					ForEach(self.availableYears, id: \.self) { year in
						Button {
							self.browsingYear = year
						} label: {
							if year == self.browsingYear {
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
				.disabled(self.availableYears.count < 1)
			}
		}
	}

	// MARK: - Picker

	/// Whether the current real-world month has already reached December for `browsingYear` — i.e.
	/// whether that year's December has necessarily happened (this year in December+, or any past year).
	private var showsYearPill: Bool {
		let currentYear = Calendar.current.component(.year, from: .now)
		if self.browsingYear < currentYear { return true }
		if self.browsingYear == currentYear { return Calendar.current.component(.month, from: .now) >= 12 }
		return false
	}

	private func monthIdentifier(_ month: Int) -> String {
		String(format: "%04d-%02d", self.browsingYear, month)
	}

	private var isFutureMonth: (Int) -> Bool {
		let now = InsightsFormat.monthIdentifier(.now)
		return { self.monthIdentifier($0) > now }
	}

	@ViewBuilder
	private var periodPicker: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 22) {
				ForEach(1...12, id: \.self) { month in
					let identifier = self.monthIdentifier(month)
					let selected = self.period == .month(identifier)

					if !self.isFutureMonth(month) {
						Group {
							Button(InsightsFormat.monthName(month)) {
								self.period = .month(identifier)
							}
							.foregroundStyle(selected ? DTColor.textPrimary : DTColor.textPrimary.opacity(0.4))
							.font(DTFont.serif(24))
							.lineLimit(1)

						}
						.disabled(self.isFutureMonth(month))
					}
				}

				if self.showsYearPill {
					let selected = self.period == .year(self.browsingYear)

					Button(String(self.browsingYear)) {
						self.period = .year(self.browsingYear)
					}
					.foregroundStyle(selected ? DTColor.textPrimary : DTColor.textPrimary.opacity(0.4))
					.font(DTFont.serif(24))
					.lineLimit(1)
				}
			}
			.padding(.vertical, 2)
		}
		.scrollClipDisabled()
	}

	// MARK: - Loading

	private func load() async {
		guard let server else {
			self.loadError = NafynError.unauthenticated
			return
		}

		self.isLoading = true
		defer { self.isLoading = false }

		do {
			switch self.period {
				case .year(let year):
					let insights = try await server.send(Insights.yearly(year: year)) as YearlyInsights
					self.yearly = insights
					self.monthly = nil
					if self.availableYears.isEmpty {
						self.availableYears = insights.availableYears
					}
				case .month(let month):
					let insights = try await server.send(Insights.monthly(month: month)) as MonthlyInsights
					self.monthly = insights
					self.yearly = nil
			}
			self.loadError = nil
		} catch {
			self.loadError = error
		}
	}

	@ContentBuilder
	private func errorView(_ error: Error) -> some View {
		VStack(spacing: 12) {
			Text(error.localizedDescription)
				.font(DTFont.system(18))
				.foregroundStyle(DTColor.textPrimary.opacity(0.7))
				.multilineTextAlignment(.center)
				.lineLimit(3)

			Button(String(localized: "retry")) {
				Task { await self.load() }
			}
			.buttonStyle(.hollow())
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	// MARK: - Sharing

	@ContentBuilder
	private var shareAction: some View {
		if let shareImage {
			ShareLink(
				item: shareImage,
				preview: SharePreview(self.recapTitle, image: shareImage)
			) {
				Label(String(localized: "insights-share"), systemImage: "square.and.arrow.up")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
		} else if self.yearly != nil || self.monthly != nil {
			Button {
				self.prepareShareImage()
			} label: {
				if self.isPreparingShare {
					ProgressView()
						.tint(DTColor.textPrimary)
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

	private var recapTitle: String {
		switch self.period {
			case .month:
				return String(localized: "monthly-summary")
			case .year:
				return String(localized: "music-year")
		}
	}

	/// Renders the share card off-screen into an `Image`, which `ShareLink` can then hand to the share
	/// sheet. Rendering is deferred until asked for — the card pulls artwork over the network, which
	/// isn't worth doing for everyone who merely opens the screen.
	private func prepareShareImage() {
		guard let summary = self.currentSummary else { return }
		self.isPreparingShare = true

		Task {
			let covers = await MusicYearShareCard.loadCovers(for: summary)

			await MainActor.run {
				let card = MusicYearShareCard(summary: summary, covers: covers)
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

	private var currentSummary: RecapSummary? {
		if let yearly, case .year = self.period {
			return RecapSummary(yearly: yearly)
		}
		if let monthly, case .month = self.period {
			return RecapSummary(monthly: monthly)
		}
		return nil
	}
}

// MARK: - Yearly body

private struct YearInsightsBody: View {
	let insights: YearlyInsights
	@Binding var showingReel: Bool

	var body: some View {
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
	}

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
		}
	}

	@ContentBuilder
	private var monthlyChart: some View {
		if self.insights.monthlyMinutes.contains(where: { $0 > 0 }) {
			VStack(alignment: .leading, spacing: 12) {
				InsightsSectionHeader(String(localized: "insights-by-month"))

				Chart(Array(self.insights.monthlyMinutes.enumerated()), id: \.offset) { index, minutes in
					BarMark(
						x: .value(String(localized: "month"), InsightsFormat.monthInitial(index + 3)),
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

	@ContentBuilder
	private var rankings: some View {
		InsightsRanking(String(localized: "top-tracks"), entities: self.insights.top.track, kind: .track, period: "year", year: self.insights.year, month: nil)
		InsightsRanking(String(localized: "top-artists"), entities: self.insights.top.artist, kind: .artist, period: "year", year: self.insights.year, month: nil)
		InsightsRanking(String(localized: "top-albums"), entities: self.insights.top.album, kind: .album, period: "year", year: self.insights.year, month: nil)
		InsightsRanking(String(localized: "top-playlists"), entities: self.insights.top.playlist, kind: .playlist, period: "year", year: self.insights.year, month: nil)
	}
}

// MARK: - Monthly body

private struct MonthInsightsBody: View {
	let insights: MonthlyInsights

	var body: some View {
		VStack(alignment: .leading, spacing: 24) {
			self.header

			if self.insights.gate.enough {
				self.totals
				self.dailyChart
				self.rankings
			} else {
				InsightsGateView(gate: self.insights.gate)
			}
		}
	}

	@ContentBuilder
	private var header: some View {
		Text(InsightsFormat.monthLabel(self.insights.month))
			.font(DTFont.serif(48))
			.foregroundStyle(DTColor.textPrimary)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ContentBuilder
	private var totals: some View {
		let totals = self.insights.totals
		let previous = self.insights.previousTotals

		LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
			InsightsStatTile(
				value: InsightsFormat.minutes(totals.totalMinutes),
				caption: String(localized: "insights-total-listening"),
				change: InsightsFormat.percentChange(from: previous.totalMinutes, to: totals.totalMinutes)
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.totalPlays),
				caption: String(localized: "insights-total-plays"),
				change: InsightsFormat.percentChange(from: previous.totalPlays, to: totals.totalPlays)
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.uniqueTracks),
				caption: String(localized: "insights-unique-tracks"),
				change: InsightsFormat.percentChange(from: previous.uniqueTracks, to: totals.uniqueTracks)
			)

			InsightsStatTile(
				value: InsightsFormat.count(totals.uniqueArtists),
				caption: String(localized: "insights-unique-artists"),
				change: InsightsFormat.percentChange(from: previous.uniqueArtists, to: totals.uniqueArtists)
			)
		}
	}

	@ContentBuilder
	private var dailyChart: some View {
		if self.insights.series.contains(where: { $0.minutes > 0 }) {
			VStack(alignment: .leading, spacing: 12) {
				InsightsSectionHeader(String(localized: "insights-by-day"))

				Chart(self.insights.series, id: \.date) { point in
					BarMark(
						x: .value(String(localized: "day"), InsightsFormat.dayLabel(point.date)),
						y: .value(String(localized: "minutes"), point.minutes)
					)
					.foregroundStyle(DTColor.accentGradient)
					.cornerRadius(4)
				}
				.chartXAxis {
					AxisMarks(values: .automatic(desiredCount: 10)) {
						AxisValueLabel()

						AxisGridLine()
					}
				}
				.chartYAxis {
					AxisMarks(position: .leading)
				}
				.frame(height: 180)
			}
		}
	}

	@ContentBuilder
	private var rankings: some View {
		InsightsRanking(String(localized: "top-tracks"), entities: self.insights.top.track, kind: .track, period: "month", year: nil, month: self.insights.month)
		InsightsRanking(String(localized: "top-artists"), entities: self.insights.top.artist, kind: .artist, period: "month", year: nil, month: self.insights.month)
		InsightsRanking(String(localized: "top-albums"), entities: self.insights.top.album, kind: .album, period: "month", year: nil, month: self.insights.month)
	}
}

// MARK: - Shared ranking section

/// One "see all"-headed ranked-entity section, shared by both the yearly and monthly bodies.
private struct InsightsRanking: View {
	let title: String
	let entities: [RankedEntity]?
	let kind: RankedEntityKind
	let period: String
	let year: Int?
	let month: String?

	init(_ title: String, entities: [RankedEntity]?, kind: RankedEntityKind, period: String, year: Int?, month: String?) {
		self.title = title
		self.entities = entities
		self.kind = kind
		self.period = period
		self.year = year
		self.month = month
	}

	var body: some View {
		if let entities, !entities.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				InsightsSectionHeader(title: self.title) {
					Button(String(localized: "see-all")) {
						Navigator.shared.send(to: .insightsTop(type: self.kind, period: self.period, year: self.year, month: self.month))
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
