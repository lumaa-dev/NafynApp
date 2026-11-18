// Made by Lumaa

import SwiftUI

/// When one word (or syllable) of a lyric is sung, in seconds on the song's clock.
///
/// Attached to the word's `Text` with `customAttribute(_:)`; `KaraokeTextRenderer` reads it back off every
/// run the word was laid out in, so the word keeps the system's wrapping, kerning and bidi.
struct WordTiming: TextAttribute {
	var start: Double
	var duration: Double

	init(start: Double, duration: Double) {
		self.start = start
		self.duration = max(0, duration)
	}

	var end: Double { self.start + self.duration }
}

extension WordTiming {
}
