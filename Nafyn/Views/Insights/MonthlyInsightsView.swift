// Made by Lumaa

import SwiftUI
import Charts
import Safyn

/// A month's listening summary from `Insights.monthly(month:)`, with the previous month alongside it.
struct MonthlyInsightsView: View {
	@Environment(\.server) private var server: NafynServer?

	/// The `YYYY-MM` month to show, or `nil` for the month in progress.
	let month: String?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Insights.monthly(month: self.month)) as MonthlyInsights
		} content: { insights, _ in
			MonthlyInsightsContent(insights: insights)
		}
		.navigationTitle(String(localized: "monthly-summary"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct MonthlyInsightsContent: View {
	let insights: MonthlyInsights

	/// The month after the one shown, unless that's still in the future.
	private var nextMonth: String? {
		let next = InsightsFormat.month(self.insights.month, offsetBy: 1)
		return next <= InsightsFormat.monthIdentifier(.now) ? next : nil
	}

	var body: some View {
		ScrollView {
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
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
	}

	@ContentBuilder
	private var header: some View {
		HStack {
			Button {
				Navigator.shared.send(to: .monthlyInsights(month: self.insights.previousMonth))
			} label: {
				Image(systemName: "chevron.left")
			}
			.tint(Color.primary)

			Spacer()

			Text(InsightsFormat.monthLabel(self.insights.month))
				.font(DTFont.serif(30))
				.foregroundStyle(DTColor.textPrimary)

			Spacer()

			Button {
				guard let nextMonth = self.nextMonth else { return }
				Navigator.shared.send(to: .monthlyInsights(month: nextMonth))
			} label: {
				Image(systemName: "chevron.right")
			}
			.tint(Color.primary)
			.disabled(self.nextMonth == nil)
		}
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
					AxisMarks(values: .automatic(desiredCount: 6))
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
		self.ranking(String(localized: "top-tracks"), entities: self.insights.top.track, kind: .track)
		self.ranking(String(localized: "top-artists"), entities: self.insights.top.artist, kind: .artist)
		self.ranking(String(localized: "top-albums"), entities: self.insights.top.album, kind: .album)
	}

	@ContentBuilder
	private func ranking(_ title: String, entities: [RankedEntity]?, kind: RankedEntityKind) -> some View {
		if let entities, !entities.isEmpty {
			VStack(alignment: .leading, spacing: 6) {
				InsightsSectionHeader(title: title) {
					Button(String(localized: "see-all")) {
						Navigator.shared.send(to: .insightsTop(type: kind, period: "month", year: nil, month: self.insights.month))
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
