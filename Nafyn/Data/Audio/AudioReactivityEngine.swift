// Made by Lumaa

import AVFoundation
import CoreMedia

/// Real-time bass/overall loudness estimate for the currently-playing item, driving
/// `CoverMeshBackground`'s subtle motion in `NowPlayingView`, plus a 6-band level signal driving the
/// mini waveform indicator in `QueuePanel`.
///
/// Both come from one `MTAudioProcessingTap` on the playing item. That same tap also runs the user's
/// equalizer (``EqualizerProcessor``) and the spectrum analyzer behind it: the levels below are measured on
/// the untouched signal, then the buffer is equalized in place and analyzed again for the EQ screen. Each of the 6 bars owns a frequency
/// range (see ``Band``), isolated by a 4th-order band-pass (a Butterworth high-pass then low-pass), so a
/// bar moves when the instruments living in that range play: kick and bass at the left, voices and
/// guitars in the middle, cymbals at the right. Ranges stay within what a speaker or headphone reproduces
/// and an ear hears (50 Hz...12 kHz), no sub-bass rumble and no ultrasonic air.
@Observable
final class AudioReactivityEngine: NSObject {
	static let shared = AudioReactivityEngine()

	/// One bar's slice of the spectrum.
	struct Band: Sendable {
		/// Lower and upper edge of the band, in Hz.
		let low: Float
		let high: Float
		/// Multiplies the band's RMS: music carries far less energy in the highs than in the lows, so
		/// without it the right-hand bars would barely move.
		let gain: Float
		/// What typically sounds in this range, for reference.
		let instruments: String
	}

	/// The 6 bars, low to high. Edges are adjacent (each band starts where the previous ends).
	static let bands: [Band] = [
		Band(low: 50, high: 140, gain: 6, instruments: "kick drum, bass guitar, synth bass, low piano"),
		Band(low: 140, high: 350, gain: 8, instruments: "bass guitar and cello body, toms, low male voice, low piano"),
		Band(low: 350, high: 900, gain: 10, instruments: "guitars, piano, snare body, male and female voice"),
		Band(low: 900, high: 2_500, gain: 14, instruments: "lead voice, violin, saxophone, guitar and piano upper range"),
		Band(low: 2_500, high: 6_000, gain: 20, instruments: "violin and flute brightness, vocal clarity, snare crack"),
		Band(low: 6_000, high: 12_000, gain: 30, instruments: "hi-hats, cymbals, strings and vocal air"),
	]

	/// Number of bars the waveform indicator renders.
	static let bandCount = AudioReactivityEngine.bands.count

	/// Smoothed low-frequency energy, roughly 0...1. Read from a `TimelineView` context, not observed
	/// per-buffer, so UI updates stay pinned to the display's own cadence.
	private(set) var bassLevel: Double = 0

	/// Smoothed overall loudness, roughly 0...1.
	private(set) var overallLevel: Double = 0

	/// The 6 bars' smoothed levels, roughly 0...1 each, in ``bands`` order.
	private(set) var bandLevels: [Double] = Array(repeating: 0, count: AudioReactivityEngine.bandCount)

	private weak var attachedItem: AVPlayerItem?

	// Audio-thread state: written only from the tap callbacks, never observed.
	@ObservationIgnored private var lowPassState: Float = 0
	@ObservationIgnored private var bassAlpha: Float = 0.02
	@ObservationIgnored private var channelStride = 1
	@ObservationIgnored private var filterBank = BandFilterBank(sampleRate: 44_100)

	private override init() {
		super.init()
	}

	/// Installs an audio tap on `item`'s first audio track. Safe to call repeatedly — replaces any
	/// previous tap. `PlayerEngine` calls this right after creating the item, well before playback needs it.
	func attach(to item: AVPlayerItem) {
		self.detach()
		// Loads the saved equalizer before the tap can ask for it: tap callbacks run off the main actor.
		_ = EqualizerEngine.shared

		let asset = item.asset
		Task {
			guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return }
			await MainActor.run {
				self.installTap(on: item, track: track)
			}
		}
	}

	func detach() {
		self.attachedItem?.audioMix = nil
		self.attachedItem = nil
		self.lowPassState = 0
		self.bassLevel = 0
		self.overallLevel = 0
		self.filterBank.reset()
		self.bandLevels = Array(repeating: 0, count: Self.bandCount)
	}

	private func installTap(on item: AVPlayerItem, track: AVAssetTrack) {
		// Another `attach(to:)` may have already superseded this one while the async track lookup above
		// was in flight (fast track skipping) — don't install a tap for a stale item.
		guard item.audioMix == nil else { return }

		var callbacks = MTAudioProcessingTapCallbacks(
			version: kMTAudioProcessingTapCallbacksVersion_0,
			clientInfo: Unmanaged.passUnretained(self).toOpaque(),
			init: audioReactivityTapInit,
			finalize: audioReactivityTapFinalize,
			prepare: audioReactivityTapPrepare,
			unprepare: audioReactivityTapUnprepare,
			process: audioReactivityTapProcess
		)

		var tap: MTAudioProcessingTap?
		let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
		guard status == noErr, let tap else { return }

		let inputParameters = AVMutableAudioMixInputParameters(track: track)
		inputParameters.audioTapProcessor = tap

		let audioMix = AVMutableAudioMix()
		audioMix.inputParameters = [inputParameters]
		item.audioMix = audioMix
		self.attachedItem = item
	}

	/// Called by the tap's `prepare` with the real stream format, so the filter corners are right at any
	/// sample rate (44.1, 48, 96 kHz...) and interleaved stereo is read one channel at a time.
	fileprivate func prepare(sampleRate: Double, channels: Int, isInterleaved: Bool) {
		let rate = Float(sampleRate > 0 ? sampleRate : 44_100)
		self.filterBank = BandFilterBank(sampleRate: rate)
		self.bassAlpha = 1 - exp(-2 * Float.pi * 150 / rate)
		self.channelStride = isInterleaved ? max(channels, 1) : 1
		self.lowPassState = 0
	}

	/// Called on every tap buffer (audio thread) with `Float32` samples; `stride` steps over the other
	/// channels of an interleaved buffer, so only one channel is analyzed. A one-pole low-pass
	/// approximates the bass envelope; the six band-pass filters feed ``bandLevels``.
	fileprivate func processSamples(_ samples: UnsafePointer<Float>, count: Int) {
		let stride = self.channelStride
		let frames = count / stride
		guard frames > 0 else { return }

		var lowPassed = self.lowPassState
		var bassEnergy: Float = 0
		var totalEnergy: Float = 0
		let alpha = self.bassAlpha

		let bank = self.filterBank
		var bandEnergies = bank.process(samples, frames: frames, stride: stride) { sample in
			lowPassed += alpha * (sample - lowPassed)
			bassEnergy += lowPassed * lowPassed
			totalEnergy += sample * sample
		}
		self.lowPassState = lowPassed

		let frameCount = Float(frames)
		let bassRMS = Double(sqrt(bassEnergy / frameCount))
		let totalRMS = Double(sqrt(totalEnergy / frameCount))
		for band in 0..<bandEnergies.count {
			bandEnergies[band] = sqrt(bandEnergies[band] / frameCount) * Self.bands[band].gain
		}
		let bandRMS = bandEnergies.map(Double.init)

		Task { @MainActor in
			// Gains chosen so typical music sits mid-range rather than pinned at 0 or 1; smoothing
			// keeps the mesh animation gliding rather than flickering per-buffer.
			let bassTarget = min(bassRMS * 7, 1)
			let overallTarget = min(totalRMS * 4, 1)
			self.bassLevel = self.bassLevel * 0.85 + bassTarget * 0.15
			self.overallLevel = self.overallLevel * 0.85 + overallTarget * 0.15

			for band in 0..<Self.bandCount {
				// square root lifts quiet passages so a soft band still shows movement
				let target = min(bandRMS[band].squareRoot(), 1)
				self.bandLevels[band] = self.bandLevels[band] * 0.7 + target * 0.3
			}
		}
	}
}

/// Six band-pass filters, each a 2nd-order Butterworth high-pass at the band's lower edge cascaded with a
/// 2nd-order Butterworth low-pass at its upper edge (24 dB/octave skirts, so a neighboring range barely
/// leaks in). Only ever touched from the audio thread, one buffer at a time.
private final class BandFilterBank {
	private struct Biquad {
		var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
		var z1: Float = 0, z2: Float = 0

		/// Transposed direct form II.
		@inline(__always)
		mutating func run(_ x: Float) -> Float {
			let y = self.b0 * x + self.z1
			self.z1 = self.b1 * x - self.a1 * y + self.z2
			self.z2 = self.b2 * x - self.a2 * y
			return y
		}
	}

	/// Two sections per band: `[high-pass, low-pass]`.
	private var sections: [Biquad]

	init(sampleRate: Float) {
		var sections: [Biquad] = []
		for band in AudioReactivityEngine.bands {
			// keep the upper edge safely below Nyquist on low sample rates
			let high = min(band.high, sampleRate * 0.45)
			sections.append(Self.butterworth(cutoff: band.low, sampleRate: sampleRate, highPass: true))
			sections.append(Self.butterworth(cutoff: high, sampleRate: sampleRate, highPass: false))
		}
		self.sections = sections
	}

	func reset() {
		for index in self.sections.indices {
			self.sections[index].z1 = 0
			self.sections[index].z2 = 0
		}
	}

	/// Runs `frames` samples (every `stride`-th float of `samples`) through every band and returns each
	/// band's summed squared output. `perSample` sees the raw sample, for the caller's own meters.
	func process(_ samples: UnsafePointer<Float>, frames: Int, stride: Int, perSample: (Float) -> Void) -> [Float] {
		var energies = [Float](repeating: 0, count: AudioReactivityEngine.bandCount)

		self.sections.withUnsafeMutableBufferPointer { sections in
			for frame in 0..<frames {
				let sample = samples[frame * stride]
				perSample(sample)

				for band in 0..<AudioReactivityEngine.bandCount {
					let filtered = sections[band * 2 + 1].run(sections[band * 2].run(sample))
					energies[band] += filtered * filtered
				}
			}
		}

		return energies
	}

	/// RBJ cookbook biquad, Q = 1/√2 (maximally flat).
	private static func butterworth(cutoff: Float, sampleRate: Float, highPass: Bool) -> Biquad {
		let w0 = 2 * Float.pi * cutoff / sampleRate
		let cosW0 = cos(w0)
		let alpha = sin(w0) / (2 * 0.70710678)

		let a0 = 1 + alpha
		var section = Biquad()
		if highPass {
			section.b0 = (1 + cosW0) / 2 / a0
			section.b1 = -(1 + cosW0) / a0
			section.b2 = section.b0
		} else {
			section.b0 = (1 - cosW0) / 2 / a0
			section.b1 = (1 - cosW0) / a0
			section.b2 = section.b0
		}
		section.a1 = -2 * cosW0 / a0
		section.a2 = (1 - alpha) / a0
		return section
	}
}

// MARK: - MTAudioProcessingTap C callbacks

// These must be plain top-level functions (no captured state) to be usable as the C function pointers
// `MTAudioProcessingTapCallbacks` expects; the tap's storage carries a `TapContext` across the boundary instead.

/// What one tap carries through the C callbacks: the shared reactivity engine and, once the stream format is
/// known, this item's own equalizer. Per tap rather than shared, so the previous item's tap being torn down
/// can't stop the next item's equalizer while a fast skip overlaps them.
private final class TapContext {
	let reactivity: AudioReactivityEngine
	var equalizer: EqualizerProcessor?

	init(reactivity: AudioReactivityEngine) {
		self.reactivity = reactivity
	}
}

private func audioReactivityTapInit(tap: MTAudioProcessingTap, clientInfo: UnsafeMutableRawPointer?, tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
	guard let clientInfo else { return }
	let reactivity = Unmanaged<AudioReactivityEngine>.fromOpaque(clientInfo).takeUnretainedValue()
	tapStorageOut.pointee = Unmanaged.passRetained(TapContext(reactivity: reactivity)).toOpaque()
}

private func audioReactivityTapFinalize(tap: MTAudioProcessingTap) {
	Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func audioReactivityTapPrepare(tap: MTAudioProcessingTap, maxFrames: CMItemCount, processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
	let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
	let format = processingFormat.pointee
	let isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
	context.reactivity.prepare(sampleRate: format.mSampleRate, channels: Int(format.mChannelsPerFrame), isInterleaved: isInterleaved)
	context.equalizer = EqualizerProcessor(description: format, maxFrames: Int(maxFrames))
}

private func audioReactivityTapUnprepare(tap: MTAudioProcessingTap) {
	let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
	context.equalizer = nil
}

private func audioReactivityTapProcess(
	tap: MTAudioProcessingTap,
	numberFrames: CMItemCount,
	flags: MTAudioProcessingTapFlags,
	bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
	numberFramesOut: UnsafeMutablePointer<CMItemCount>,
	flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
	var timeRange = CMTimeRange.invalid
	let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut)
	guard status == noErr else { return }

	let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()

	let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
	guard let buffer = buffers.first, let rawData = buffer.mData else { return }

	// Assumes non-interleaved/interleaved Float32 PCM, which is what `AVMutableAudioMixInputParameters`
	// taps deliver by default (`AVAudioMix` doesn't alter sample format). If a track's tap ever hands
	// back a different format this simply reads garbage into an already-clamped, already-smoothed
	// signal — never a crash, since the byte count read is derived from the same buffer's own size.
	let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
	let floatData = rawData.assumingMemoryBound(to: Float.self)
	context.reactivity.processSamples(floatData, count: floatCount)

	// After the levels above, so the cover animation keeps following the original recording rather than
	// the user's EQ curve.
	context.equalizer?.process(bufferListInOut, frames: numberFramesOut.pointee)
}
