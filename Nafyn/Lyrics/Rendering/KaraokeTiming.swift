// Made by Lumaa

import SwiftUI

/// The karaoke animations as pure functions of the song's time: no state, no scheduling, so pausing, seeking
/// and any playback rate need nothing more than a different `time`.
enum KaraokeTiming {
	/// How a run of a word is drawn at a given time.
	enum Reveal: Equatable {
		/// All in the inactive style.
		case unlit
		/// All in the active style.
		case lit
		/// Lit up to `edge`, fading to unlit over `softness` after it, both in widths of the run, measured
		/// from the run's reading-direction start.
		case partial(edge: Double, softness: Double)
	}

	// CSS's named curves, which Braccato's defaults use.
	static let ease = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1), endControlPoint: UnitPoint(x: 0.25, y: 1))
	static let easeInOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
	static let easeOut = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))

	// MARK: Sweep

	/// How far through its swipe a word is (0...1). The swipe starts `leadRatio` of the word's duration early
	/// and lasts `durationRatio` of it, linearly. A word with no duration is all or nothing at its start.
	static func sweepProgress(time: Double, word: WordTiming, sweep: KaraokeConfiguration.Sweep) -> Double {
		let length = sweep.durationRatio * word.duration
		guard length > 0 else { return time >= word.start ? 1 : 0 }
		let begin = word.start - sweep.leadRatio * word.duration
		return Self.clamp((time - begin) / length)
	}

	/// Where the lit edge is, in widths of the word, at `progress`.
	static func litEdge(progress: Double, sweep: KaraokeConfiguration.Sweep) -> Double {
		sweep.edgeFrom + (sweep.edgeTo - sweep.edgeFrom) * progress
	}

	/// The time at which the lit edge reaches `position` (in widths of the word).
	static func time(edgeReaches position: Double, word: WordTiming, sweep: KaraokeConfiguration.Sweep) -> Double {
		let span = sweep.edgeTo - sweep.edgeFrom
		guard span > 0 else { return word.start }
		let begin = word.start - sweep.leadRatio * word.duration
		return begin + (position - sweep.edgeFrom) / span * sweep.durationRatio * word.duration
	}

	/// How one run of a word is drawn. `offset` is where the run starts along the word in reading order, and
	/// `runWidth` / `wordWidth` are in points, so the soft edge is relative to the whole word and a word split
	/// over two lines sweeps one part after the other. Nothing is lit before the word starts: its lit copy
	/// appears at once at the word's start, then the edge moves.
	static func reveal(
		time: Double,
		word: WordTiming,
		sweep: KaraokeConfiguration.Sweep,
		offset: Double,
		runWidth: Double,
		wordWidth: Double
	) -> Reveal {
		guard time >= word.start else { return .unlit }
		guard runWidth > 0, wordWidth > 0 else { return .lit }

		let edgeInWord = Self.litEdge(progress: Self.sweepProgress(time: time, word: word, sweep: sweep), sweep: sweep)
		let edge = (edgeInWord * wordWidth - offset) / runWidth
		let softness = max(0, sweep.softness) * wordWidth / runWidth
		if edge >= 1 { return .lit }
		if edge + softness <= 0 { return .unlit }
		return .partial(edge: edge, softness: softness)
	}

	// MARK: Glow

	/// The glow's strength (1 when it starts, 0 when it's gone). It starts when the lit edge reaches the word
	/// and fades over `max(durationRatio * duration, minimumDuration)` with CSS `ease`. Short words don't glow.
	static func glowIntensity(time: Double, word: WordTiming, glow: KaraokeConfiguration.Glow, sweep: KaraokeConfiguration.Sweep) -> Double {
		guard glow.isEnabled, word.duration >= glow.minimumWordDuration else { return 0 }
		let start = max(word.start, Self.time(edgeReaches: 0, word: word, sweep: sweep))
		let duration = max(glow.durationRatio * word.duration, glow.minimumDuration)
		guard duration > 0, time >= start, time < start + duration else { return 0 }
		return 1 - Self.ease.value(at: (time - start) / duration)
	}

	// MARK: Letter wave

	/// Lift (in em, negative is up) and scale of letter `index` of `count` in a word. Each letter's wave starts
	/// when the soft edge touches it and peaks around when the lit edge has crossed it; it then settles at
	/// `settle`, where it stays.
	static func letterWave(
		time: Double,
		word: WordTiming,
		letter index: Int,
		of count: Int,
		wave: KaraokeConfiguration.LetterWave,
		sweep: KaraokeConfiguration.Sweep
	) -> (lift: CGFloat, scale: CGFloat) {
		guard wave.isEnabled, count > 0 else { return (0, 1) }
		let touched = Self.time(edgeReaches: Double(index) / Double(count) - sweep.softness, word: word, sweep: sweep)
		let lit = Self.time(edgeReaches: Double(index + 1) / Double(count), word: word, sweep: sweep)
		let lighting = max(0, lit - touched)
		let crestAt = Self.clamp(wave.crestPosition, 0.01, 0.99)
		let rise = wave.duration * crestAt

		let start: Double
		let duration: Double
		if lighting > rise {
			start = touched
			duration = lighting / crestAt
		} else {
			start = touched + lighting - rise
			duration = wave.duration
		}
		guard duration > 0, time > start else { return (0, 1) }

		let emphasis = word.duration >= wave.emphasisMinimumWordDuration ? wave.emphasisScale : 1
		let local = Self.clamp((time - start) / duration)
		if local < crestAt {
			let eased = CGFloat(Self.easeInOut.value(at: local / crestAt))
			return (wave.crest * eased, 1 + (emphasis - 1) * eased)
		}
		let eased = CGFloat(Self.easeOut.value(at: (local - crestAt) / (1 - crestAt)))
		return (wave.crest + (wave.settle - wave.crest) * eased, emphasis + (1 - emphasis) * eased)
	}

	// MARK: Wobble

	/// Horizontal scale and shift (in em) of a word: a stretch to the peak, eased back by `settleAt`, over
	/// `duration` from the word's start with CSS `ease` on the whole.
	static func wobble(time: Double, word: WordTiming, wobble: KaraokeConfiguration.Wobble) -> (scaleX: CGFloat, offsetX: CGFloat) {
		guard wobble.isEnabled, word.duration < wobble.maximumWordDuration, wobble.duration > 0 else { return (1, 0) }
		let local = (time - word.start) / wobble.duration
		guard local > 0, local < 1 else { return (1, 0) }

		let progress = Self.ease.value(at: local)
		let peakAt = Self.clamp(wobble.peakAt, 0.001, 1)
		let settleAt = max(peakAt, Self.clamp(wobble.settleAt))
		let amount: Double
		if progress < peakAt {
			amount = progress / peakAt
		} else if progress < settleAt {
			amount = 1 - Self.easeInOut.value(at: (progress - peakAt) / (settleAt - peakAt))
		} else {
			amount = 0
		}
		return (1 + (wobble.peakScaleX - 1) * CGFloat(amount), wobble.peakOffsetX * CGFloat(amount))
	}

	// MARK: Window

	/// From when to when anything of these words moves, or `nil` for no words. Outside it a line can be drawn
	/// with a fixed time; inside it, it needs a frame-by-frame clock.
	static func animationInterval(for words: [WordTiming], configuration: KaraokeConfiguration) -> ClosedRange<Double>? {
		var lower = Double.infinity
		var upper = -Double.infinity
		for word in words {
			let begin = word.start - configuration.sweep.leadRatio * word.duration
			var end = begin + configuration.sweep.durationRatio * word.duration
			if configuration.glow.isEnabled {
				end = max(end, word.end + max(configuration.glow.durationRatio * word.duration, configuration.glow.minimumDuration))
			}
			if configuration.letterWave.isEnabled {
				let litEnd = Self.time(edgeReaches: 1, word: word, sweep: configuration.sweep)
				let firstTouch = min(begin, Self.time(edgeReaches: -configuration.sweep.softness, word: word, sweep: configuration.sweep))
				let crestAt = Self.clamp(configuration.letterWave.crestPosition, 0.01, 0.99)
				end = max(end, litEnd + max(configuration.letterWave.duration, (litEnd - firstTouch) / crestAt))
			}
			if configuration.wobble.isEnabled {
				end = max(end, word.start + configuration.wobble.duration)
			}
			lower = min(lower, begin)
			upper = max(upper, end)
		}
		return lower <= upper ? lower...upper : nil
	}

	static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
		min(max(value, lower), upper)
	}
}
