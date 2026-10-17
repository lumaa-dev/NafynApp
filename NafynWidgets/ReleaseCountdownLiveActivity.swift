// Made by Lumaa

import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island countdown to a followed release. The server starts it 3 hours before the
/// release (push-to-start) and flips it to "Out now" at the release moment.
struct NafynReleaseCountdownLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: NafynReleaseCountdownAttributes.self) { context in
			ReleaseLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
				.padding(16)
				.activityBackgroundTint(Color.black.opacity(0.85))
				.activitySystemActionForegroundColor(.white)
				.widgetURL(Self.url(for: context.attributes))
		} dynamicIsland: { context in
			let isOut = Self.isOut(context.state, isStale: context.isStale)

			return DynamicIsland {
				DynamicIslandExpandedRegion(.leading, priority: 1.0) {
					VStack(alignment: .leading, spacing: 1) {
						Text(context.attributes.title)
							.font(.headline)
							.lineLimit(1)
						Text(context.attributes.artistName)
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.padding(.leading, 2.0)
					.dynamicIsland(verticalPlacement: .belowIfTooWide)
				}
				DynamicIslandExpandedRegion(.trailing) {
					ReleaseTimer(state: context.state, isOut: isOut)
						.font(.title2.weight(.semibold))
						.multilineTextAlignment(.trailing)
						.frame(height: 55, alignment: .trailing)
						.padding(.trailing, 2.0)
				}
			} compactLeading: {
				Image(systemName: isOut ? "checkmark.circle.fill" : "clock")
			} compactTrailing: {
				if isOut {
					Text("out-now")
						.font(.caption2)
				} else {
					Text(timerInterval: Self.range(for: context.state), countsDown: true)
						.monospacedDigit()
						.frame(width: 52)
						.font(.caption2)
				}
			} minimal: {
				Image(systemName: isOut ? "checkmark.circle.fill" : "clock")
			}
			.widgetURL(Self.url(for: context.attributes))
		}
	}

	static func isOut(_ state: NafynReleaseCountdownAttributes.ContentState, isStale: Bool) -> Bool {
		state.released || isStale
	}

	/// `Text(timerInterval:)` needs `lower <= upper`, so a release moment already behind us collapses to an
	/// empty range instead of crashing the activity.
	static func range(for state: NafynReleaseCountdownAttributes.ContentState) -> ClosedRange<Date> {
		let now = Date()
		return now...max(now, state.releaseDate)
	}

	static func url(for attributes: NafynReleaseCountdownAttributes) -> URL? {
		URL(string: "nafyn://\(attributes.type)/\(attributes.musicbrainzId)")
	}
}

private struct ReleaseTimer: View {
	let state: NafynReleaseCountdownAttributes.ContentState
	let isOut: Bool

	var body: some View {
		if self.isOut {
			Text("out-now")
		} else {
			// counts down by itself on-device, so the server doesn't push once a second
			Text(timerInterval: NafynReleaseCountdownLiveActivity.range(for: self.state), countsDown: true)
				.monospacedDigit()
		}
	}
}

private struct ReleaseLockScreenView: View {
	let attributes: NafynReleaseCountdownAttributes
	let state: NafynReleaseCountdownAttributes.ContentState
	let isStale: Bool

	var body: some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				Text(self.attributes.title)
					.font(.headline)
					.lineLimit(1)
				Text(self.attributes.artistName)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer(minLength: 0)

			ReleaseTimer(state: self.state, isOut: NafynReleaseCountdownLiveActivity.isOut(self.state, isStale: self.isStale))
				.font(.title2.weight(.semibold))
				.multilineTextAlignment(.trailing)
				.frame(alignment: .trailing)
		}
		.foregroundStyle(.white)
	}
}

#Preview(as: .dynamicIsland(.expanded), using: NafynReleaseCountdownAttributes.cmiygl) {
	NafynReleaseCountdownLiveActivity()
} contentStates: {
	NafynReleaseCountdownAttributes.ContentState.wks
	NafynReleaseCountdownAttributes.ContentState.hrs
}
