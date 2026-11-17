// Made by Lumaa

import SwiftUI

/// One word or syllable of a lyric line, as `KaraokeText` lays it out.
struct KaraokeWord: Hashable {
	var text: String
	/// `nil` draws the word in the inactive style.
	var timing: WordTiming?
	/// A space follows it (vs. a syllable glued to the next one).
	var endsWord: Bool
}

/// A lyric line drawn by `KaraokeTextRenderer`. Only the line whose words are moving reads a clock every
/// frame; any other line is drawn once at a fixed time.
struct KaraokeText: View {
	enum Clock {
		/// Draw at this time; nothing on the line is moving.
		case fixed(Double)
		/// Ask `time` for the song's time at each frame's date, unless `isPaused`.
		case live(isPaused: Bool, time: (Date) -> Double)
	}

	let text: Text
	let clock: Clock
	var configuration = KaraokeConfiguration()

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var cache = KaraokeLayoutCache()

	init(_ text: Text, clock: Clock, configuration: KaraokeConfiguration = KaraokeConfiguration()) {
		self.text = text
		self.clock = clock
		self.configuration = configuration
	}

	init(words: [KaraokeWord], clock: Clock, configuration: KaraokeConfiguration = KaraokeConfiguration()) {
		self.init(Self.text(words), clock: clock, configuration: configuration)
	}

	var body: some View {
		let configuration = self.configuration.reducingMotion(self.reduceMotion)
		switch self.clock {
		case .fixed(let time):
			self.text.textRenderer(KaraokeTextRenderer(time: time, configuration: configuration, cache: self.cache))
		case .live(let isPaused, let time):
			TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { context in
				self.text.textRenderer(KaraokeTextRenderer(time: time(context.date), configuration: configuration, cache: self.cache))
			}
		}
	}

	/// The words as one `Text`, each carrying its `WordTiming`, so the system wraps, kerns and orders them
	/// (bidi) like any text. Style it (`font`, `foregroundStyle`) like any `Text`.
	static func text(_ words: [KaraokeWord]) -> Text {
		var interpolation = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: words.count * 2)
		for (index, word) in words.enumerated() {
			var piece = Text(verbatim: word.text)
			if let timing = word.timing {
				piece = piece.customAttribute(timing)
			}
			interpolation.appendInterpolation(piece)
			if word.endsWord, index < words.count - 1 {
				interpolation.appendInterpolation(Text(verbatim: " "))
			}
		}
		// Joins the pieces without the deprecated `Text + Text`. The key ("%@%@…") is built at run time, so it is
		// never extracted into a String Catalog, and looked up in a table that doesn't exist, so it is never
		// translated: it always formats to the pieces themselves.
		return Text(LocalizedStringKey(stringInterpolation: interpolation), tableName: "KaraokeTextVerbatim")
	}
}
