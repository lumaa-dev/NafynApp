// Made by Lumaa

import AVFoundation
import CoreMedia
#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

/// Real-time bass/overall loudness estimate for the currently-playing item, driving
/// `CoverMeshBackground`'s subtle motion in `NowPlayingView`, plus a 6-band level signal driving the
/// mini waveform indicator in `QueuePanel`.
///
/// Two sources feed the 6-band signal, never mixed for the same track:
/// - iOS 27+: `MusicUnderstanding`'s `instrumentActivity` analysis, run once per track against the
///   full asset and sampled by playback time — genuine per-instrument activity, not a fabricated
///   spectrum, but only available after that one-time analysis completes.
/// - Every OS version (and the fallback while/if the above is unavailable or still running): the same
///   `MTAudioProcessingTap` this class already installs for `bassLevel`/`overallLevel`, extended with 5
///   more one-pole low-pass filters at increasing corner frequencies so adjacent-band subtraction yields
///   a genuine (if approximate) multiband envelope from the live PCM — cheap enough to run every buffer.
@Observable
final class AudioReactivityEngine: NSObject {
	static let shared = AudioReactivityEngine()

	/// Number of bars the waveform indicator renders.
	static let bandCount = 6

	/// Smoothed low-frequency energy, roughly 0...1. Read from a `TimelineView` context, not observed
	/// per-buffer, so UI updates stay pinned to the display's own cadence.
	private(set) var bassLevel: Double = 0

	/// Smoothed overall loudness, roughly 0...1.
	private(set) var overallLevel: Double = 0

	/// Tap-derived 6-band envelope, roughly 0...1 each — always live, on every OS version, as the
	/// fallback source for `bandLevels(at:trackId:)`.
	private(set) var tapBandLevels: [Double] = Array(repeating: 0, count: AudioReactivityEngine.bandCount)

	private weak var attachedItem: AVPlayerItem?
	private var lowPassState: Float = 0
	/// One running low-pass state per band corner frequency, for the `tapBandLevels` subtractive filter bank.
	private var bandLowPassState: [Float] = Array(repeating: 0, count: AudioReactivityEngine.bandCount)

	#if canImport(MusicUnderstanding)
	/// Type-erased `InstrumentActivityCache?` — that concrete type is `@available(iOS 27...)`-gated (it
	/// holds `MusicUnderstandingSession.TimedValue`), so it can't be named directly in a stored property
	/// that must also compile for older OS versions, same reasoning as `PlayerEngine`'s `mediaSessionBox`.
	private var instrumentActivityCache: Any? = nil
	private var instrumentAnalysisTask: Task<Void, Never>? = nil
	#endif

	private override init() {
		super.init()
	}

	/// Installs an audio tap on `item`'s first audio track, and (iOS 27+) kicks off a one-time
	/// `MusicUnderstanding` instrument-activity analysis of the same item keyed to `trackId`. Safe to
	/// call repeatedly — replaces any previous tap/analysis. No-op if the asset's tracks aren't
	/// available synchronously (e.g. still resolving); `PlayerEngine` calls this right after creating
	/// the item, well before playback needs it.
	func attach(to item: AVPlayerItem, trackId: String) {
		self.detach()

		let asset = item.asset
		Task {
			guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return }
			await MainActor.run {
				self.installTap(on: item, track: track)
			}
		}

		#if canImport(MusicUnderstanding)
		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
			self.runInstrumentActivityAnalysis(item: item, trackId: trackId)
		}
		#endif
	}

	func detach() {
		self.attachedItem?.audioMix = nil
		self.attachedItem = nil
		self.lowPassState = 0
		self.bassLevel = 0
		self.overallLevel = 0
		self.bandLowPassState = Array(repeating: 0, count: Self.bandCount)
		self.tapBandLevels = Array(repeating: 0, count: Self.bandCount)

		#if canImport(MusicUnderstanding)
		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
			self.instrumentAnalysisTask?.cancel()
			self.instrumentAnalysisTask = nil
			self.instrumentActivityCache = nil
		}
		#endif
	}

	/// The 6 bars' current levels (roughly 0...1 each) for `trackId` at `playbackTime` — the single entry
	/// point the waveform view calls every frame. Prefers the cached `MusicUnderstanding` analysis for
	/// the matching track when it's ready; otherwise (older OS, analysis still running or failed) falls
	/// back to the live tap-derived bands, which are always kept up to date regardless.
	func bandLevels(at playbackTime: TimeInterval, trackId: String?) -> [Double] {
		#if canImport(MusicUnderstanding)
		if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *),
			let cache = self.instrumentActivityCache as? InstrumentActivityCache, cache.trackId == trackId {
			return cache.levels(at: playbackTime)
		}
		#endif
		return self.tapBandLevels
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

	/// Corner frequencies (Hz) for the 6-band subtractive filter bank, low to high, log-spaced across a
	/// typical music spectrum — approximate by construction (no FFT), tuned for a visually alive spread
	/// rather than precise band-pass edges.
	private static let bandCornerFrequencies: [Float] = [80, 200, 500, 1200, 3000, 8000]

	/// `alpha = 1 - e^(-2π·fc/fs)` for each corner, at a typical 44.1 kHz sample rate — same one-pole
	/// low-pass formula as the existing bass filter below, just at 6 different corners.
	private static let bandAlphas: [Float] = AudioReactivityEngine.bandCornerFrequencies.map { fc in
		1 - exp(-2 * Float.pi * fc / 44_100)
	}

	/// Called on every tap buffer (audio thread) with interleaved `Float32` samples. A one-pole
	/// low-pass filter approximates a bass-band envelope — cheap enough to run per-sample without an
	/// FFT, and plenty for driving a slow, smooth visual rather than precise spectral analysis. The same
	/// pass over the buffer also feeds 6 more low-pass filters at increasing corners; the difference
	/// between adjacent filters' outputs approximates that band's energy (a classic subtractive envelope
	/// follower), feeding `tapBandLevels`.
	fileprivate func processSamples(_ samples: UnsafePointer<Float>, count: Int) {
		guard count > 0 else { return }

		var lowPassed = self.lowPassState
		var bassEnergy: Float = 0
		var totalEnergy: Float = 0
		// ~150 Hz corner at a typical 44.1 kHz sample rate: alpha = 1 - e^(-2π·fc/fs).
		let alpha: Float = 0.02

		var bandStates = self.bandLowPassState
		var bandEnergies = Array(repeating: Float(0), count: Self.bandCount)

		for index in 0..<count {
			let sample = samples[index]
			lowPassed += alpha * (sample - lowPassed)
			bassEnergy += lowPassed * lowPassed
			totalEnergy += sample * sample

			var previousBand: Float = 0
			for band in 0..<Self.bandCount {
				bandStates[band] += Self.bandAlphas[band] * (sample - bandStates[band])
				let bandOutput = bandStates[band] - previousBand
				bandEnergies[band] += bandOutput * bandOutput
				previousBand = bandStates[band]
			}
		}
		self.lowPassState = lowPassed
		self.bandLowPassState = bandStates

		let bassRMS = Double(sqrt(bassEnergy / Float(count)))
		let totalRMS = Double(sqrt(totalEnergy / Float(count)))
		let bandRMS = bandEnergies.map { Double(sqrt($0 / Float(count))) }

		Task { @MainActor in
			// Gains chosen so typical music sits mid-range rather than pinned at 0 or 1; smoothing
			// keeps the mesh animation gliding rather than flickering per-buffer.
			let bassTarget = min(bassRMS * 7, 1)
			let overallTarget = min(totalRMS * 4, 1)
			self.bassLevel = self.bassLevel * 0.85 + bassTarget * 0.15
			self.overallLevel = self.overallLevel * 0.85 + overallTarget * 0.15

			for band in 0..<Self.bandCount {
				let target = min(bandRMS[band] * 9, 1)
				self.tapBandLevels[band] = self.tapBandLevels[band] * 0.8 + target * 0.2
			}
		}
	}

	#if canImport(MusicUnderstanding)
	/// Runs a one-time `MusicUnderstanding` instrument-activity analysis of `item`'s asset, caching the
	/// result keyed to `trackId` once it completes. Fire-and-forget: if a newer `attach(to:trackId:)`
	/// supersedes this item before the analysis finishes, the result is discarded on arrival instead of
	/// racing the new track's own cache.
	@available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
	private func runInstrumentActivityAnalysis(item: AVPlayerItem, trackId: String) {
		self.instrumentAnalysisTask = Task {
			do {
				let session = try await MusicUnderstandingSession(asset: item.asset)
				let result = try await session.analyze(for: [.instrumentActivity])
				guard let activity = result.instrumentActivity, !Task.isCancelled else { return }
				let cache = InstrumentActivityCache(trackId: trackId, activity: activity)

				await MainActor.run {
					guard self.attachedItem === item else { return }
					self.instrumentActivityCache = cache
				}
			} catch {
				// Analysis unavailable/failed for this item (unsupported source, cancelled, etc.) — the
				// live tap-derived `tapBandLevels` stays the fallback, so the waveform still animates.
			}
		}
	}
	#endif
}

#if canImport(MusicUnderstanding)
/// Sampled `InstrumentActivityResult`, pre-flattened to plain `(seconds, value)` arrays (sorted by
/// time) so `levels(at:)` can binary-search instead of walking `CMTime`-keyed structures every frame.
@available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
private struct InstrumentActivityCache {
	let trackId: String
	private let vocal: [(time: Double, value: Float)]
	private let drum: [(time: Double, value: Float)]
	private let bass: [(time: Double, value: Float)]
	private let other: [(time: Double, value: Float)]

	init(trackId: String, activity: InstrumentActivityResult) {
		self.trackId = trackId
		self.vocal = Self.flatten(activity.activity[.vocal])
		self.drum = Self.flatten(activity.activity[.drum])
		self.bass = Self.flatten(activity.activity[.bass])
		self.other = Self.flatten(activity.activity[.other])
	}

	private static func flatten(_ samples: [MusicUnderstandingSession.TimedValue<Float>]?) -> [(time: Double, value: Float)] {
		(samples ?? []).map { (CMTimeGetSeconds($0.time), $0.value) }
	}

	/// Maps the 4 instrument categories onto the 6 bars in a fixed low-to-high spread — bass, a
	/// bass/drum blend, drum, vocal, a vocal/other blend, other — so 4 discrete signals still read as a
	/// smooth left-to-right sweep rather than 2 dead bars.
	private static let barWeights: [[Double]] = [
		[1.0, 0.0, 0.0, 0.0],
		[0.5, 0.5, 0.0, 0.0],
		[0.0, 1.0, 0.0, 0.0],
		[0.0, 0.0, 1.0, 0.0],
		[0.0, 0.0, 0.5, 0.5],
		[0.0, 0.0, 0.0, 1.0],
	]

	func levels(at time: TimeInterval) -> [Double] {
		let categories = [
			Double(Self.value(in: self.bass, at: time)),
			Double(Self.value(in: self.drum, at: time)),
			Double(Self.value(in: self.vocal, at: time)),
			Double(Self.value(in: self.other, at: time)),
		]
		return Self.barWeights.map { weights in
			zip(weights, categories).reduce(0) { $0 + $1.0 * $1.1 }
		}
	}

	/// Linearly interpolates the nearest samples around `time`, clamping to the first/last sample outside
	/// the analyzed range.
	private static func value(in samples: [(time: Double, value: Float)], at time: Double) -> Float {
		guard !samples.isEmpty else { return 0 }
		if time <= samples[0].time { return samples[0].value }
		if time >= samples[samples.count - 1].time { return samples[samples.count - 1].value }

		var low = 0
		var high = samples.count - 1
		while high - low > 1 {
			let mid = (low + high) / 2
			if samples[mid].time <= time {
				low = mid
			} else {
				high = mid
			}
		}

		let (t0, v0) = samples[low]
		let (t1, v1) = samples[high]
		let ratio = t1 > t0 ? Float((time - t0) / (t1 - t0)) : 0
		return v0 + (v1 - v0) * ratio
	}
}
#endif

// MARK: - MTAudioProcessingTap C callbacks

/// These must be plain top-level functions (no captured state) to be usable as the C function pointers
/// `MTAudioProcessingTapCallbacks` expects; `clientInfo`/the tap's storage carries the `AudioReactivityEngine`
/// instance across the boundary instead.

private func audioReactivityTapInit(tap: MTAudioProcessingTap, clientInfo: UnsafeMutableRawPointer?, tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
	tapStorageOut.pointee = clientInfo
}

private func audioReactivityTapFinalize(tap: MTAudioProcessingTap) {}

private func audioReactivityTapPrepare(tap: MTAudioProcessingTap, maxFrames: CMItemCount, processingFormat: UnsafePointer<AudioStreamBasicDescription>) {}

private func audioReactivityTapUnprepare(tap: MTAudioProcessingTap) {}

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

	let engine = Unmanaged<AudioReactivityEngine>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()

	let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
	guard let buffer = buffers.first, let rawData = buffer.mData else { return }

	// Assumes non-interleaved/interleaved Float32 PCM, which is what `AVMutableAudioMixInputParameters`
	// taps deliver by default (`AVAudioMix` doesn't alter sample format). If a track's tap ever hands
	// back a different format this simply reads garbage into an already-clamped, already-smoothed
	// signal — never a crash, since the byte count read is derived from the same buffer's own size.
	let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
	let floatData = rawData.assumingMemoryBound(to: Float.self)
	engine.processSamples(floatData, count: floatCount)
}
