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
	/// Spreads a line's time over its words when only the line is timed: each word gets a share of the line in
	/// proportion to its length (whitespace not counted), back to back, so the last one ends with the line.
	/// Words with no visible characters get no time; if no word has any, the line is split evenly.
	static func distribute(lineStart: Double, lineEnd: Double, words: [String]) -> [WordTiming] {
		guard !words.isEmpty else { return [] }
		let lineDuration = max(0, lineEnd - lineStart)
		let weights = words.map { word in Double(word.filter { !$0.isWhitespace }.count) }
		let total = weights.reduce(0, +)
		let shares = total > 0 ? weights.map { $0 / total } : Array(repeating: 1 / Double(words.count), count: words.count)

		var timings: [WordTiming] = []
		timings.reserveCapacity(words.count)
		var elapsed = 0.0
		for share in shares {
			let duration = lineDuration * share
			timings.append(WordTiming(start: lineStart + elapsed, duration: duration))
			elapsed += duration
		}
		return timings
	}
}
