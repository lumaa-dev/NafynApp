// Made by Lumaa

import SwiftUI

/// The time left before the next lyric during an instrumental break: a ring that fills up as the break goes on
/// (like the request Live Activity's progress ring), the seconds left counting down in its middle. As tall as
/// one line of lyrics, so the panel doesn't jump when the break gives way to the next line.
///
/// DESIGN.md has no section for it; it follows "Animations" (short ease-out changes, fades only with Reduce
/// Motion) and the panel's lyric colors.
struct InstrumentalBreakView: View {
	let startTime: TimeInterval
	let endTime: TimeInterval
	/// The font of the lyrics around it: the ring takes the height of one of their lines.
	let lyricFont: Font
	let isPaused: Bool
	/// The song's time at a frame's date.
	let time: (Date) -> TimeInterval

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ScaledMetric(relativeTo: .title) private var lineWidth: CGFloat = 3.5

	var body: some View {
		// an invisible line of lyrics sizes the ring
		Text(verbatim: "0")
			.font(self.lyricFont)
			.hidden()
			.frame(maxWidth: .infinity, alignment: .leading)
			.overlay(alignment: .leading) {
				TimelineView(.animation(minimumInterval: nil, paused: self.isPaused)) { context in
					let now = self.time(context.date)
					let duration = self.endTime - self.startTime
					let fraction = duration > 0 ? min(max((now - self.startTime) / duration, 0), 1) : 1
					let remaining = max(0, Int((self.endTime - now).rounded(.up)))

					self.ring(fraction: fraction, remaining: remaining)
				}
				.aspectRatio(1, contentMode: .fit)
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(String(localized: "lyrics-instrumental-break"))
	}

	private func ring(fraction: Double, remaining: Int) -> some View {
		ZStack {
			Circle()
				.stroke(DTColor.textPrimary.opacity(0.4), lineWidth: self.lineWidth)

			Circle()
				.trim(from: 0, to: fraction)
				.stroke(DTColor.textPrimary, style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round))
				.rotationEffect(.degrees(-90))

			Text(remaining, format: .number)
				.font(DTFont.system(15, weight: .semibold, design: .rounded))
				.monospacedDigit()
				.minimumScaleFactor(0.4)
				.lineLimit(1)
				.foregroundStyle(DTColor.textPrimary)
				.padding(self.lineWidth * 1.5)
				.contentTransition(self.reduceMotion ? .opacity : .numericText(countsDown: true))
				.animation(.easeOut(duration: 0.25), value: remaining)
		}
		.padding(self.lineWidth / 2)
	}
}

#Preview("Instrumental break") {
	let start = Date.now
	VStack(alignment: .leading, spacing: 18) {
		Text(verbatim: "The line before the break")
			.font(DTFont.serif(32).bold())
			.foregroundStyle(DTColor.textPrimary)
		InstrumentalBreakView(startTime: 0, endTime: 12, lyricFont: DTFont.serif(32).bold(), isPaused: false) { date in
			date.timeIntervalSince(start).truncatingRemainder(dividingBy: 12)
		}
		Text(verbatim: "The line after it")
			.font(DTFont.serif(32).bold())
			.foregroundStyle(DTColor.textPrimary.opacity(0.4))
	}
	.padding()
	.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	.background(Color.black)
	.preferredColorScheme(.dark)
}
