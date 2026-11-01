// Made by Lumaa

import SwiftUI
import Safyn

/// One headline number ("14 h 22 m", "312 plays") with its caption, and an optional change indicator
/// against the previous period.
struct InsightsStatTile: View {
	let value: String
	let caption: String
	var change: Int? = nil

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(self.value)
				.font(DTFont.serif(30))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.minimumScaleFactor(0.6)

			Text(self.caption)
				.font(DTFont.system(13))
				.foregroundStyle(DTColor.textPrimary.opacity(0.55))

			if let change, change != 0 {
				Label(
					String(localized: "\(abs(change))-percent"),
					systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right"
				)
				.font(DTFont.system(12))
				.foregroundStyle(change > 0 ? DTColor.statusSuccess : DTColor.textPrimary.opacity(0.45))
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(DTSpacing.buttonVertical)
		.background(DTColor.surfaceSelect, in: RoundedRectangle(cornerRadius: DTRadius.textArea))
	}
}

/// A section title in the Insights screens, optionally with a trailing "see all"-style action.
struct InsightsSectionHeader<Trailing: View>: View {
	let title: String
	@ViewBuilder var trailing: () -> Trailing

	var body: some View {
		HStack(alignment: .firstTextBaseline) {
			Text(self.title)
				.font(DTFont.serifItalic(25))
				.foregroundStyle(DTColor.textPrimary)

			Spacer()

			self.trailing()
		}
	}
}

extension InsightsSectionHeader where Trailing == EmptyView {
	init(_ title: String) {
		self.init(title: title) { EmptyView() }
	}
}

/// One entry of a ranked list (top track/album/artist/playlist), with its rank, artwork, and play count.
struct RankedEntityRow: View {
	@Environment(\.server) private var server: NafynServer?

	let entity: RankedEntity
	var onTap: (() -> Void)? = nil

	var body: some View {
		Button {
			self.onTap?()
		} label: {
			HStack(spacing: 12) {
				Text(String(self.entity.rank))
					.font(DTFont.serif(22))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					.frame(width: 28, alignment: .trailing)

				Group {
					// an artist ranked by name rather than MBID has nothing to look up
					if self.entity.entityType == .artist {
						ArtistPhoto(
							artistId: self.entity.entityId.contains("-") ? self.entity.entityId : nil,
							fallback: self.entity.cover.flatMap(URL.init(string:)),
							cornerRadius: DTRadius.pill
						)
					} else {
						CoverImage(url: self.entity.cover.flatMap(URL.init(string:)), cornerRadius: 10)
					}
				}
				.frame(width: 44, height: 44)

				VStack(alignment: .leading, spacing: 2) {
					Text(self.entity.title ?? self.entity.entityId)
						.font(DTFont.serif(19))
						.foregroundStyle(DTColor.textPrimary)
						.lineLimit(1)

					Text(self.subtitle)
						.font(DTFont.system(13))
						.foregroundStyle(DTColor.textPrimary.opacity(0.55))
						.lineLimit(1)
				}

				Spacer(minLength: 8)

				if self.entity.isFirstEver == true {
					Image(systemName: "sparkles")
						.font(DTFont.system(13))
						.foregroundStyle(DTColor.statusWaiting)
						.accessibilityLabel(String(localized: "insights-first-ever"))
				}
			}
			.padding(.vertical, 6)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(self.onTap == nil)
		.libraryItemMenu(
			item: self.entity.libraryItem,
			play: self.entity.libraryItem.map { item in { [server = self.server] in try await item.playbackQueue(server: server) } }
		)
	}

	private var subtitle: String {
		let plays = String(localized: "\(self.entity.playCount)-plays")
		guard let entitySubtitle = self.entity.subtitle, !entitySubtitle.isEmpty else { return plays }
		return "\(entitySubtitle) · \(plays)"
	}
}

/// The "keep listening" state shown while a period hasn't met the server's ranking threshold yet.
struct InsightsGateView: View {
	let gate: EnoughDataGate

	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: "waveform")
				.font(DTFont.system(34))
				.foregroundStyle(DTColor.textPrimary.opacity(0.4))

			Text(String(localized: "insights-not-enough-title"))
				.font(DTFont.serif(24))
				.foregroundStyle(DTColor.textPrimary)

			Text(String(localized: "insights-not-enough-body"))
				.font(DTFont.system(14))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				.multilineTextAlignment(.center)

			VStack(spacing: 8) {
				InsightsGateProgress(
					caption: String(localized: "insights-gate-tracks"),
					current: self.gate.uniqueTracks,
					needed: self.gate.needUniqueTracks
				)

				InsightsGateProgress(
					caption: String(localized: "insights-gate-minutes"),
					current: self.gate.minutes,
					needed: self.gate.needMinutes
				)
			}
			.padding(.top, 4)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 32)
		.padding(.horizontal, DTSpacing.buttonVertical)
		.background(DTColor.surfaceSelect, in: RoundedRectangle(cornerRadius: DTRadius.textArea))
	}
}

private struct InsightsGateProgress: View {
	let caption: String
	let current: Int
	let needed: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(self.caption)
				Spacer()
				Text("\(InsightsFormat.count(self.current)) / \(InsightsFormat.count(self.needed))")
			}
			.font(DTFont.system(12))
			.foregroundStyle(DTColor.textPrimary.opacity(0.55))

			ProgressView(value: Double(min(self.current, self.needed)), total: Double(max(self.needed, 1)))
				.tint(DTColor.textPrimary)
		}
	}
}
