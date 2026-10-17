// Made by Lumaa

import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island for a download request. The server starts, updates and ends it by push.
struct NafynRequestLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: NafynRequestActivityAttributes.self) { context in
			HStack {
				self.songInfo(context)
					.frame(maxWidth: .infinity, alignment: .leading)

				if context.state.stage == .completed || context.state.stage == .failed {
					self.stageIcon(context.state.stage)
						.imageScale(.large)
						.font(.title)
						.foregroundStyle(self.stageColor(context.state.stage))
				} else {
					self.progress(context)
				}
			}
			.padding(16)
			.activityBackgroundTint(Color(hex: "2A2A27"))
			.activitySystemActionForegroundColor(.white)
			.widgetURL(RequestStageStyle.url(for: context.attributes))
		} dynamicIsland: { context in
			DynamicIsland {
				DynamicIslandExpandedRegion(.leading, priority: 1.0) {
					self.songInfo(context)
						.frame(maxHeight: .infinity)
						.padding(.leading, 2.0)
						.dynamicIsland(verticalPlacement: .belowIfTooWide)
				}
				DynamicIslandExpandedRegion(.trailing) {
					self.progress(context)
				}
			} compactLeading: {
				self.stageIcon(context.state.stage)
					.resizable()
					.scaledToFit()
					.frame(width: 20, height: 20)
			} compactTrailing: {
				RequestProgressRing(fraction: self.fraction(context), lineWidth: 2.5) {
					Text("\(context.state.trackIndex ?? 0)")
						.font(.system(size: 10, weight: .semibold, design: .rounded))
						.monospacedDigit()
						.minimumScaleFactor(0.5)
						.lineLimit(1)
						.contentTransition(.numericText(value: Double(context.state.trackIndex ?? 0)))
				}
				.frame(width: 22, height: 22)
			} minimal: {
				RequestProgressRing(fraction: self.fraction(context), lineWidth: 3) {
					self.stageIcon(context.state.stage)
						.resizable()
						.scaledToFit()
						.padding(5)
				}
				.frame(width: 24, height: 24)
			}
			.widgetURL(RequestStageStyle.url(for: context.attributes))
		}
	}

	@ViewBuilder
	private func songInfo(_ context: ActivityViewContext<NafynRequestActivityAttributes>) -> some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(context.attributes.title)
				.font(.headline)
				.lineLimit(1)
			Text(context.attributes.artistName)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}

	/// Same maths as the lock screen gauge, as a 0...1 fraction.
	private func fraction(_ context: ActivityViewContext<NafynRequestActivityAttributes>) -> Double {
		let current = Double(context.state.trackIndex ?? 0) + (context.state.progress ?? 0.0)
		let total = Double(context.state.trackCount ?? 0) + 1.0
		return min(max(current / total, 0), 1)
	}

	@ViewBuilder
	private func progress(_ context: ActivityViewContext<NafynRequestActivityAttributes>) -> some View {
		let current: Double = Double(context.state.trackIndex ?? 0) + (context.state.progress ?? 0.0)

		Gauge(value: current, in: 0...Double(context.state.trackCount ?? 0) + 1.0) {
			self.stageIcon(context.state.stage)
		} currentValueLabel: {
			Text("\(context.state.trackIndex ?? 0)")
				.foregroundColor(Color.primary)
				.contentTransition(.numericText(value: Double(context.state.trackCount ?? 0)))
		}
		.gaugeStyle(.accessoryCircularCapacity)
		.tint(Color.blue)
	}

	private func stageIcon(_ stage: NafynRequestActivityAttributes.ContentState.Stage) -> Image {
		switch stage {
			case .waiting: Image(systemName: "clock")
			case .searching: Image(systemName: "magnifyingglass")
			case .downloading: Image(systemName: "arrow.down.circle")
			case .processing: Image(systemName: "gearshape")
			case .completed: Image(systemName: "checkmark.circle.fill")
			case .failed: Image(systemName: "xmark.circle.fill")
		}
	}

	private func stageColor(_ stage: NafynRequestActivityAttributes.ContentState.Stage) -> Color {
		switch stage {
			case .completed: Color.green
			case .failed: Color.red
			default: Color.primary
		}
	}
}

/// Circular capacity ring for the compact and minimal Dynamic Island, where `Gauge` renders unreliably.
/// Plain shapes, so it scales to any frame and keeps working when the island resizes.
private struct RequestProgressRing<Center: View>: View {
	let fraction: Double
	let lineWidth: CGFloat
	@ViewBuilder var center: Center

	var body: some View {
		ZStack {
			Circle()
				.stroke(Color.blue.opacity(0.3), lineWidth: self.lineWidth)
			Circle()
				.trim(from: 0, to: self.fraction)
				.stroke(Color.blue, style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round))
				.rotationEffect(.degrees(-90))
			self.center
				.foregroundStyle(Color.white)
		}
		.padding(self.lineWidth / 2)
		.animation(.smooth, value: self.fraction)
	}
}

extension RequestProgressRing where Center == EmptyView {
	init(fraction: Double, lineWidth: CGFloat) {
		self.init(fraction: fraction, lineWidth: lineWidth) { EmptyView() }
	}
}

private enum RequestStageStyle {
	/// Tapping opens the item's screen, or the Requests tab when the type is unknown.
	static func url(for attributes: NafynRequestActivityAttributes) -> URL? {
		URL(string: "nafyn://requests")
	}

	static func title(_ stage: NafynRequestActivityAttributes.ContentState.Stage) -> LocalizedStringKey {
		switch stage {
			case .waiting: "status-waiting"
			case .searching: "status-searching"
			case .downloading: "status-downloading"
			case .processing: "status-processing"
			case .completed: "status-completed"
			case .failed: "status-failed"
		}
	}
}

#Preview(as: .dynamicIsland(.expanded), using: NafynRequestActivityAttributes.cmiygl) {
	NafynRequestLiveActivity()
} contentStates: {
	NafynRequestActivityAttributes.ContentState.lifestyleTrainers
	NafynRequestActivityAttributes.ContentState.sorryNotSorry
}

extension Color {
	init(hex: String, opacity: Double = 1) {
		let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
		var value: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&value)
		let r = Double((value >> 16) & 0xFF) / 255
		let g = Double((value >> 8) & 0xFF) / 255
		let b = Double(value & 0xFF) / 255
		self.init(red: r, green: g, blue: b, opacity: opacity)
	}
}
