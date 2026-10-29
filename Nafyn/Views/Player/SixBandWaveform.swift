// Made by Lumaa

import SwiftUI
import Safyn

/// The small 6-bar "now playing" indicator next to the queue header, mirroring the animated waveform
/// glyph Apple Music shows beside its "Playing from" label — genuinely driven by `AudioReactivityEngine`,
/// whose six bars each follow a frequency range (kick and bass on the left up to cymbals on the right),
/// not a looping decorative animation. Sits at its minimum height when nothing is playing, matching the
/// system glyph's paused state.
struct SixBandWaveform: View {
	var tint: Color = DTColor.textPrimary
	var barWidth: CGFloat = 2.5
	var spacing: CGFloat = 2
	var height: CGFloat = 14

	var body: some View {
		TimelineView(.animation(paused: !PlayerEngine.shared.isPlaying)) { _ in
			let levels = AudioReactivityEngine.shared.bandLevels

			HStack(alignment: .bottom, spacing: self.spacing) {
				ForEach(0..<levels.count, id: \.self) { index in
					Capsule()
						.fill(self.tint)
						.frame(width: self.barWidth, height: self.barHeight(for: levels[index]))
				}
			}
			.frame(height: self.height, alignment: .bottom)
			.animation(.easeInOut(duration: 0.12), value: levels)
		}
	}

	private func barHeight(for level: Double) -> CGFloat {
		let minHeight = self.height * 0.18
		guard PlayerEngine.shared.isPlaying else { return minHeight }
		return minHeight + (self.height - minHeight) * CGFloat(max(0, min(1, level)))
	}
}
