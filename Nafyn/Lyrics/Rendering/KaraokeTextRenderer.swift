// Made by Lumaa

import SwiftUI

/// Draws a lyric line (one `Text` whose words carry a `WordTiming`) as a karaoke swipe, as a pure function of
/// `time`. SwiftUI lays the text out (wrapping, kerning, bidi); this walks `layout → line → run` and draws every
/// run against its own bounds, so wrapped lines and right-to-left runs sweep in reading order.
///
/// Only a run whose edge is crossing it right now, or that glows, is drawn through an offscreen layer; every
/// other run is a plain `draw(run)`.
struct KaraokeTextRenderer: TextRenderer {
	var time: Double
	var configuration: KaraokeConfiguration
	/// Per-layout data, computed once per layout instead of every frame.
	var cache: KaraokeLayoutCache

	/// Approximate line height of a font, in em: turns a run's typographic height into its font size.
	private static let lineHeightPerEm: CGFloat = 1.2

	private static let reveal = Gradient(colors: [.black, .clear])

	var animatableData: Double {
		get { self.time }
		set { self.time = newValue }
	}

	var displayPadding: EdgeInsets {
		// em measured against the largest lyric sizes; the renderer has no font size before `draw`
		let padding = self.configuration.overhang * 48
		return EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
	}

	func draw(layout: Text.Layout, in context: inout GraphicsContext) {
		let runs = self.cache.runs(for: layout)
		var index = 0
		for line in layout {
			for run in line {
				if index < runs.count {
					self.draw(run, info: runs[index], in: context)
				} else {
					context.draw(run)
				}
				index += 1
			}
		}
	}

	private func draw(_ run: Text.Layout.Run, info: KaraokeLayoutCache.RunInfo, in context: GraphicsContext) {
		guard let word = info.timing else {
			// spaces and untimed text
			var dimmed = context
			dimmed.opacity *= self.configuration.inactiveOpacity
			dimmed.draw(run)
			return
		}

		let bounds = run.typographicBounds
		let em = (bounds.ascent + bounds.descent) / Self.lineHeightPerEm
		let isRightToLeft = run.layoutDirection == .rightToLeft
		var context = context

		if !isRightToLeft {
			let wobble = KaraokeTiming.wobble(time: self.time, word: word, wobble: self.configuration.wobble)
			if wobble.scaleX != 1 || wobble.offsetX != 0 {
				let center = bounds.rect.midX
				context.translateBy(x: center + wobble.offsetX * em, y: 0)
				context.scaleBy(x: wobble.scaleX, y: 1)
				context.translateBy(x: -center, y: 0)
			}
		}

		let reveal = KaraokeTiming.reveal(
			time: self.time,
			word: word,
			sweep: self.configuration.sweep,
			offset: info.offsetInWord,
			runWidth: bounds.width,
			wordWidth: info.wordWidth
		)
		let glow = KaraokeTiming.glowIntensity(time: self.time, word: word, glow: self.configuration.glow, sweep: self.configuration.sweep)

		switch reveal {
		case .unlit:
			self.drawDimmed(run, info: info, word: word, em: em, in: context)

		case .lit:
			var lit = context
			if glow > 0 { self.addGlow(glow, em: em, to: &lit) }
			self.drawGlyphs(run, info: info, word: word, em: em, in: lit)

		case .partial(let edge, let softness):
			self.drawDimmed(run, info: info, word: word, em: em, in: context)

			var lit = context
			let minX = bounds.rect.minX
			let width = bounds.width
			let x: (Double) -> CGFloat = { isRightToLeft ? bounds.rect.maxX - $0 * width : minX + $0 * width }

			if softness > 0 {
				let overhang = em * self.configuration.overhang + 2
				let area = bounds.rect.insetBy(dx: -overhang, dy: -overhang)
				lit.clipToLayer { mask in
					mask.fill(
						Path(area),
						with: .linearGradient(
							Self.reveal,
							startPoint: CGPoint(x: x(edge), y: area.midY),
							endPoint: CGPoint(x: x(edge + softness), y: area.midY)
						)
					)
				}
			} else {
				// a hard edge needs no layer
				let overhang = em * self.configuration.overhang + 2
				let start = isRightToLeft ? x(edge) : bounds.rect.minX - overhang
				let end = isRightToLeft ? bounds.rect.maxX + overhang : x(edge)
				lit.clip(to: Path(CGRect(x: start, y: bounds.rect.minY - overhang, width: max(0, end - start), height: bounds.rect.height + overhang * 2)))
			}
			if glow > 0 { self.addGlow(glow, em: em, to: &lit) }
			self.drawGlyphs(run, info: info, word: word, em: em, in: lit)
		}
	}

	private func drawDimmed(_ run: Text.Layout.Run, info: KaraokeLayoutCache.RunInfo, word: WordTiming, em: CGFloat, in context: GraphicsContext) {
		var dimmed = context
		dimmed.opacity *= self.configuration.inactiveOpacity
		self.drawGlyphs(run, info: info, word: word, em: em, in: dimmed)
	}

	private func addGlow(_ intensity: Double, em: CGFloat, to context: inout GraphicsContext) {
		let glow = self.configuration.glow
		context.addFilter(.shadow(color: glow.color.opacity(intensity), radius: max(0.5, glow.radius * em * CGFloat(intensity))))
	}

	/// The run at once, or letter by letter while the letter wave is on.
	private func drawGlyphs(_ run: Text.Layout.Run, info: KaraokeLayoutCache.RunInfo, word: WordTiming, em: CGFloat, in context: GraphicsContext) {
		guard self.configuration.letterWave.isEnabled else {
			context.draw(run)
			return
		}

		let count = run.count
		let isRightToLeft = run.layoutDirection == .rightToLeft
		for index in 0..<count {
			let slice = run[index]
			let letter = info.firstLetter + (isRightToLeft ? count - 1 - index : index)
			let wave = KaraokeTiming.letterWave(
				time: self.time,
				word: word,
				letter: letter,
				of: info.wordLetterCount,
				wave: self.configuration.letterWave,
				sweep: self.configuration.sweep
			)
			guard wave.lift != 0 || wave.scale != 1 else {
				context.draw(slice)
				continue
			}
			let bounds = slice.typographicBounds
			var letterContext = context
			letterContext.translateBy(x: bounds.rect.midX, y: bounds.origin.y + wave.lift * em)
			letterContext.scaleBy(x: wave.scale, y: wave.scale)
			letterContext.translateBy(x: -bounds.rect.midX, y: -bounds.origin.y)
			letterContext.draw(slice)
		}
	}
}

/// What `KaraokeTextRenderer` needs to know about every run of a layout, worked out once per layout: which word
/// it belongs to, and where it sits along that word. Held by the view across frames.
final class KaraokeLayoutCache {
	struct RunInfo {
		var timing: WordTiming?
		/// Where the run starts along its word, in points, in reading order.
		var offsetInWord: Double = 0
		/// The width of the whole word over all its runs, in points.
		var wordWidth: Double = 0
		/// Index of the run's first glyph among its word's glyphs, and how many glyphs the word has.
		var firstLetter: Int = 0
		var wordLetterCount: Int = 0
	}

	private var layout: Text.Layout?
	private var cachedRuns: [RunInfo] = []

	/// The runs of `layout` in drawing order (line by line, run by run).
	func runs(for layout: Text.Layout) -> [RunInfo] {
		if let cached = self.layout, cached == layout { return self.cachedRuns }
		self.layout = layout
		self.cachedRuns = Self.makeRuns(layout)
		return self.cachedRuns
	}

	private struct Measured {
		var drawIndex: Int
		var timing: WordTiming?
		/// The run's first character in the string, for reading order.
		var firstCharacter: Text.Layout.CharacterIndex?
		var width: Double
		var glyphs: Int
	}

	private static func makeRuns(_ layout: Text.Layout) -> [RunInfo] {
		var logical: [Measured] = []
		for line in layout {
			for run in line {
				logical.append(Measured(
					drawIndex: logical.count,
					timing: run[WordTiming.self],
					firstCharacter: run.characterIndices.min(),
					width: run.typographicBounds.width,
					glyphs: run.count
				))
			}
		}

		// In string order, a word's runs come in reading order whatever line they were wrapped to or however
		// bidi reordered them; consecutive runs with the same timing are one word.
		logical.sort { lhs, rhs in
			switch (lhs.firstCharacter, rhs.firstCharacter) {
			case let (lhs?, rhs?): return lhs < rhs
			case (.some, nil): return true
			default: return false
			}
		}

		var infos = Array(repeating: RunInfo(), count: logical.count)
		var start = 0
		while start < logical.count {
			var end = start + 1
			if logical[start].timing != nil {
				while end < logical.count, logical[end].timing == logical[start].timing { end += 1 }
			}
			let wordWidth = logical[start..<end].reduce(0) { $0 + $1.width }
			let wordGlyphs = logical[start..<end].reduce(0) { $0 + $1.glyphs }
			var offset = 0.0
			var letter = 0
			for item in logical[start..<end] {
				infos[item.drawIndex] = RunInfo(
					timing: item.timing,
					offsetInWord: offset,
					wordWidth: wordWidth,
					firstLetter: letter,
					wordLetterCount: wordGlyphs
				)
				offset += item.width
				letter += item.glyphs
			}
			start = end
		}
		return infos
	}
}
