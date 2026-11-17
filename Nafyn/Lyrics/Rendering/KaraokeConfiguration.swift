// Made by Lumaa

import SwiftUI

/// Everything `KaraokeTextRenderer` animates, after Braccato's defaults (`docs/lyrics-text-renderer.md`).
/// Lengths in `em` are relative to the font size of the run being drawn, so they follow Dynamic Type.
struct KaraokeConfiguration: Hashable {
	/// The karaoke swipe: a soft edge that crosses each word along its reading direction.
	struct Sweep: Hashable {
		/// The swipe starts this fraction of the word's duration before the word.
		var leadRatio: Double = 0.1
		/// The swipe lasts this multiple of the word's duration.
		var durationRatio: Double = 1.6
		/// Where the lit edge is, in widths of the word, when the swipe starts and ends. Past both ends of the
		/// word so its first and last glyphs reach fully unlit and fully lit.
		var edgeFrom: Double = -0.2
		var edgeTo: Double = 1.4
		/// Width of the soft edge, in widths of the word.
		var softness: Double = 0.2
	}

	/// A halo that blooms from the word as the swipe reaches it, then shrinks away.
	struct Glow: Hashable {
		var isEnabled = true
		/// Only words held at least this long glow.
		var minimumWordDuration: Double = 1.5
		/// Halo radius when it starts, in em.
		var radius: CGFloat = 0.27
		var color: Color = .primary
		/// The glow lasts `max(durationRatio * word duration, minimumDuration)`.
		var durationRatio: Double = 1.2
		var minimumDuration: Double = 1.2
	}

	/// Each letter lifts as the swipe crosses it and settles slightly above the baseline.
	struct LetterWave: Hashable {
		var isEnabled = false
		/// Lift at the crest and at rest, in em (negative is up).
		var crest: CGFloat = -0.05
		var settle: CGFloat = -0.02
		/// Share of a letter's wave spent rising to the crest.
		var crestPosition: Double = 0.4
		var duration: Double = 0.9
		/// Letters of held words also swell to this scale at the crest.
		var emphasisScale: CGFloat = 1.11
		var emphasisMinimumWordDuration: Double = 1.5
	}

	/// A short horizontal stretch of the word as it starts. Not applied to right-to-left runs or held words.
	struct Wobble: Hashable {
		var isEnabled = false
		var duration: Double = 1
		var peakScaleX: CGFloat = 1.025
		/// Horizontal shift at the peak, in em.
		var peakOffsetX: CGFloat = 0.05
		/// Where the peak and the settle fall, as fractions of `duration`.
		var peakAt: Double = 0.125
		var settleAt: Double = 0.75
		/// Words held at least this long don't wobble.
		var maximumWordDuration: Double = 1.5
	}

	var sweep = Sweep()
	var glow = Glow()
	var letterWave = LetterWave()
	var wobble = Wobble()
	/// Words not reached yet are drawn in the text's own style at this opacity.
	var inactiveOpacity: Double = 0.4

	/// The same configuration with every optional effect off when `reduceMotion` is on. The swipe stays: it
	/// carries the timing.
	func reducingMotion(_ reduceMotion: Bool) -> KaraokeConfiguration {
		guard reduceMotion else { return self }
		var configuration = self
		configuration.glow.isEnabled = false
		configuration.letterWave.isEnabled = false
		configuration.wobble.isEnabled = false
		return configuration
	}

	/// How far, in em, the enabled effects can draw past the glyphs' bounds.
	var overhang: CGFloat {
		var overhang: CGFloat = 0
		if self.glow.isEnabled { overhang = max(overhang, self.glow.radius * 3) }
		if self.letterWave.isEnabled {
			overhang = max(overhang, abs(self.letterWave.crest) + (self.letterWave.emphasisScale - 1))
		}
		if self.wobble.isEnabled { overhang = max(overhang, self.wobble.peakOffsetX + (self.wobble.peakScaleX - 1)) }
		return overhang
	}
}
