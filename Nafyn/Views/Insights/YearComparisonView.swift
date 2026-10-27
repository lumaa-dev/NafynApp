// Made by Lumaa

import SwiftUI
import Charts
import Safyn

/// Side-by-side totals for several years, from `Insights.compareYears(years:)`, with each year's
/// per-month minutes overlaid on one chart.
struct YearComparisonView: View {
	@Environment(\.server) private var server: NafynServer?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Insights.compareYears()) as [YearComparisonEntry]
		} content: { entries, _ in
			YearComparisonContent(entries: entries)
		}
		.navigationTitle(String(localized: "insights-compare"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct YearComparisonContent: View {
	let entries: [YearComparisonEntry]

	/// One (year, month, minutes) point per month per year, flattened for the overlaid line chart.
	private var points: [MonthPoint] {
		self.entries.flatMap { entry in
			entry.monthlyMinutes.enumerated().map { index, minutes in
				MonthPoint(year: entry.year, month: index + 1, minutes: minutes)
			}
		}
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				if self.entries.isEmpty {
					Text(String(localized: "insights-no-data"))
						.font(DTFont.system(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 40)
				} else {
					self.chart
					self.table
				}
			}
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn()
		.background(DTColor.background.ignoresSafeArea())
	}

	@ContentBuilder
	private var chart: some View {
		VStack(alignment: .leading, spacing: 12) {
			InsightsSectionHeader(String(localized: "insights-by-month"))

			Chart(self.points) { point in
				LineMark(
					x: .value(String(localized: "month"), point.month),
					y: .value(String(localized: "minutes"), point.minutes)
				)
				.foregroundStyle(by: .value(String(localized: "year"), String(point.year)))
				.interpolationMethod(.catmullRom)

				PointMark(
					x: .value(String(localized: "month"), point.month),
					y: .value(String(localized: "minutes"), point.minutes)
				)
				.foregroundStyle(by: .value(String(localized: "year"), String(point.year)))
				.symbolSize(20)
			}
			.chartXAxis {
				AxisMarks(values: Array(1...12)) { value in
					AxisValueLabel {
						if let month = value.as(Int.self) {
							Text(InsightsFormat.monthInitial(month))
						}
					}
				}
			}
			.chartYAxis {
				AxisMarks(position: .leading)
			}
			.frame(height: 220)
		}
	}

	@ContentBuilder
	private var table: some View {
		VStack(alignment: .leading, spacing: 12) {
			InsightsSectionHeader(String(localized: "insights-totals"))

			ForEach(self.entries, id: \.year) { entry in
				VStack(alignment: .leading, spacing: 8) {
					Button {
						Navigator.shared.send(to: .musicYear(year: entry.year))
					} label: {
						HStack {
							Text(String(entry.year))
								.font(DTFont.serif(26))
								.foregroundStyle(DTColor.textPrimary)

							Spacer()

							Image(systemName: "chevron.right")
								.font(DTFont.system(13))
								.foregroundStyle(DTColor.textPrimary.opacity(0.4))
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)

					HStack(spacing: 16) {
						self.metric(InsightsFormat.minutes(entry.totalMinutes), caption: String(localized: "insights-total-listening"))
						self.metric(InsightsFormat.count(entry.totalPlays), caption: String(localized: "insights-total-plays"))
						self.metric(InsightsFormat.count(entry.uniqueArtists), caption: String(localized: "insights-unique-artists"))
					}
				}
				.padding(DTSpacing.buttonVertical)
				.background(DTColor.surfaceSelect, in: RoundedRectangle(cornerRadius: DTRadius.textArea))
			}
		}
	}

	@ContentBuilder
	private func metric(_ value: String, caption: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(value)
				.font(DTFont.system(15, weight: .medium))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.minimumScaleFactor(0.7)

			Text(caption)
				.font(DTFont.system(11))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private struct MonthPoint: Identifiable {
		let year: Int
		let month: Int
		let minutes: Int

		var id: String { "\(self.year)-\(self.month)" }
	}
}
