// Made by Lumaa

import SwiftUI
import Safyn

/// A Replay Mix: the user's top 100 tracks for a year, or the All-Time mix.
///
/// Read-only by design server-side — a Replay Mix isn't a row in the playlists table, so there is no
/// rename/reorder/add/delete to offer here, not even for an administrator. The live current-year mix is
/// rebuilt every Monday; archived years are frozen as they stood when that year ended.
struct ReplayMixView: View {
	@Environment(\.server) private var server: NafynServer?

	/// A four-digit year, the literal `"all-time"`, or `nil` for the live current-year mix.
	let year: String?

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			if let year {
				return try await server.send(Insights.archivedReplayMix(year: year)) as ReplayMix
			}
			return try await server.send(Insights.replayMix) as ReplayMix
		} skeleton: {
			AnyView(SkeletonTrackRows())
		} content: { mix, _ in
			ReplayMixContent(mix: mix, isLive: self.year == nil)
		}
		.navigationTitle(String(localized: "replay-mix"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct ReplayMixContent: View {
	let mix: ReplayMix
	let isLive: Bool

	/// Only entries still in the library can be queued — an entry whose track has since left it stays
	/// listed (the mix is a record of what was played) but has no media to stream.
	private var playableTracks: [MediaRow] {
		self.mix.entries.compactMap(\.media)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				self.header

				LazyVStack(spacing: 0) {
					ForEach(self.mix.entries) { entry in
						TrackRow(
							coverURL: entry.media?.highResCoverURL ?? entry.cover.flatMap(URL.init(string:)),
							index: String(entry.position + 1),
							title: entry.media?.title ?? entry.title ?? entry.trackId,
							subtitle: entry.media?.artistName ?? entry.subtitle,
							duration: entry.media?.duration ?? 0,
							dimmed: !entry.available
						) {
							self.play(entry)
						} trailing: {
							if !entry.available {
								Image(systemName: "exclamationmark.triangle")
									.font(DTFont.system(13))
									.foregroundStyle(DTColor.textPrimary.opacity(0.4))
									.accessibilityLabel(String(localized: "replay-mix-unavailable"))
							}
						}
					}
				}

				if !self.mix.entries.isEmpty {
					Text(String(localized: "replay-mix-readonly"))
						.font(DTFont.system(12))
						.foregroundStyle(DTColor.textPrimary.opacity(0.45))
						.frame(maxWidth: .infinity, alignment: .center)
						.padding(.vertical, 8)
				}
			}
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.background(DTColor.background.ignoresSafeArea())
		.toolbar {
			if let archive = self.mix.archive, archive.count > 1 {
				ToolbarItem(placement: .primaryAction) {
					Menu {
						ForEach(archive, id: \.id) { summary in
							Button(self.label(for: summary)) {
								Navigator.shared.send(to: .replayMix(year: self.destination(for: summary)))
							}
						}
					} label: {
						Image(systemName: "clock.arrow.circlepath")
					}
					.tint(Color.primary)
				}
			}
		}
	}

	@ContentBuilder
	private var header: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(self.mix.isAllTime ? String(localized: "replay-mix-all-time") : String(self.mix.year))
				.font(DTFont.serif(44))
				.foregroundStyle(DTColor.textPrimary)

			Text(String(localized: "\(self.mix.entries.count)-tracks-count"))
				.font(DTFont.system(14))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			if let refreshedAt = self.mix.refreshedAt {
				Text(
					self.isLive
						? String(localized: "replay-mix-refreshed-\(InsightsFormat.relative(millis: refreshedAt))")
						: String(localized: "replay-mix-frozen-\(InsightsFormat.relative(millis: refreshedAt))")
				)
				.font(DTFont.system(12))
				.foregroundStyle(DTColor.textPrimary.opacity(0.45))
			}

			if !self.playableTracks.isEmpty {
				HStack(spacing: 10) {
					Button {
						guard let first = self.playableTracks.first else { return }
						PlayerEngine.shared.play(first, queue: self.playableTracks)
					} label: {
						Label(String(localized: "play"), systemImage: "play.fill")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.filled())

					Button {
						let shuffled = self.playableTracks.shuffled()
						guard let first = shuffled.first else { return }
						PlayerEngine.shared.play(first, queue: shuffled)
					} label: {
						Label(String(localized: "shuffle"), systemImage: "shuffle")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.hollow())
				}
				.padding(.top, 4)
			}
		}
	}

	private func play(_ entry: ReplayEntry) {
		guard let media = entry.media else { return }
		// Queue from this entry onward, skipping entries that have left the library.
		let queue = self.mix.entries
			.filter { $0.position >= entry.position }
			.compactMap(\.media)
		PlayerEngine.shared.play(media, queue: queue)
	}

	private func label(for summary: ReplayMix.ArchiveSummary) -> String {
		guard let year = summary.year, year > 0 else { return String(localized: "replay-mix-all-time") }
		return String(year)
	}

	/// The `year` path parameter for an archived mix: `"all-time"` for the all-time mix, otherwise the
	/// year, except for the current year's live mix which is fetched from the live endpoint instead.
	private func destination(for summary: ReplayMix.ArchiveSummary) -> String? {
		guard let year = summary.year, year > 0 else { return "all-time" }
		let currentYear = Calendar.current.component(.year, from: .now)
		return year == currentYear ? nil : String(year)
	}
}
