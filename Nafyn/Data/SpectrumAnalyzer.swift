// Made by Lumaa

import Accelerate
import AVFoundation
import Foundation
import os

/// Where the equalizer's frequency axis lives, shared by the analyzer (which resamples an FFT onto it) and the
/// visualizer (which draws it) so a bin and the pixel it lands on always agree.
///
/// The axis is logarithmic and each equalizer band owns one octave-wide column, so a band centered on
/// `lowestBand` sits at the middle of the first column: `x = (log2(f / lowestBand) + 0.5) / bandCount`.
nonisolated enum EQScale {
	/// Equalizer band centers, octave-spaced (the axis math above relies on that).
	static let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
	static let bandCount = EQScale.bandFrequencies.count

	/// Number of points the spectrum is resampled to.
	static let spectrumPointCount = 96

	private static let anchor = EQScale.bandFrequencies[0]

	/// Frequency at a normalized horizontal position (0 = left edge, 1 = right edge).
	static func frequency(at x: Float) -> Float {
		EQScale.anchor * exp2(x * Float(EQScale.bandCount) - 0.5)
	}

	/// Normalized horizontal position of a frequency.
	static func position(of frequency: Float) -> Float {
		(log2(frequency / EQScale.anchor) + 0.5) / Float(EQScale.bandCount)
	}
}

/// Thread-safe hand-off of the latest spectrum from the audio thread to the UI. The audio thread only ever
/// *tries* the lock, so it never waits on the UI: a missed publish is replaced by the next one 20 ms later.
nonisolated final class SpectrumStore: @unchecked Sendable {
	static let shared = SpectrumStore()

	private struct State {
		var levels = [Float](repeating: 0, count: EQScale.spectrumPointCount)
		var stamp: CFAbsoluteTime = 0
	}

	private let state = OSAllocatedUnfairLock(initialState: State())

	/// Audio thread. Copies in place, so nothing is allocated.
	func publish(_ levels: UnsafePointer<Float>) {
		nonisolated(unsafe) let levels = levels
		_ = self.state.withLockIfAvailable { state in
			state.levels.withUnsafeMutableBufferPointer { destination in
				destination.baseAddress?.update(from: levels, count: destination.count)
			}
			state.stamp = CFAbsoluteTimeGetCurrent()
		}
	}

	/// UI. Returns a private copy (never the stored array, which would make the audio thread copy-on-write
	/// it) and the time it was published.
	func read() -> (levels: [Float], stamp: CFAbsoluteTime) {
		self.state.withLock { state in
			(state.levels.withUnsafeBufferPointer { Array($0) }, state.stamp)
		}
	}
}

/// Turns the stream of samples the equalizer outputs into ``EQScale/spectrumPointCount`` log-spaced levels
/// (0...1) with a Hann-windowed FFT. Lives on the audio thread: every buffer is preallocated, `feed` never
/// allocates or locks.
nonisolated final class SpectrumAnalyzer {
	private static let log2Size: vDSP_Length = 12
	private static let size = 1 << Int(SpectrumAnalyzer.log2Size)
	/// New samples between two FFTs: 1024 at 44.1 kHz is ~43 spectra per second.
	private static let hop = 1_024

	/// dBFS mapped to 0 and 1 on screen.
	private static let floorDecibels: Float = -90
	private static let ceilingDecibels: Float = -25

	private struct PointRange {
		var low: Int
		var high: Int
		/// Weight of `high` when the point is narrower than one bin (linear interpolation).
		var fraction: Float
		var interpolates: Bool
		/// Spectral tilt that evens out music's natural roll-off, so the highs show up next to the bass.
		var tilt: Float
	}

	private let setup: FFTSetup
	private let sampleRate: Float
	private let window: UnsafeMutablePointer<Float>
	private let ring: UnsafeMutablePointer<Float>
	private let frame: UnsafeMutablePointer<Float>
	private let real: UnsafeMutablePointer<Float>
	private let imaginary: UnsafeMutablePointer<Float>
	private let magnitudes: UnsafeMutablePointer<Float>
	private let levels: UnsafeMutablePointer<Float>
	private var ranges: [PointRange] = []

	private var writeIndex = 0
	private var sinceLastTransform = 0

	init?(sampleRate: Double) {
		guard sampleRate > 0, let setup = vDSP_create_fftsetup(SpectrumAnalyzer.log2Size, FFTRadix(kFFTRadix2)) else { return nil }
		let size = SpectrumAnalyzer.size
		self.setup = setup
		self.sampleRate = Float(sampleRate)

		self.window = .allocate(capacity: size)
		self.ring = .allocate(capacity: size)
		self.frame = .allocate(capacity: size)
		self.real = .allocate(capacity: size / 2)
		self.imaginary = .allocate(capacity: size / 2)
		self.magnitudes = .allocate(capacity: size / 2)
		self.levels = .allocate(capacity: EQScale.spectrumPointCount)

		vDSP_hann_window(self.window, vDSP_Length(size), 0)
		self.ring.initialize(repeating: 0, count: size)
		self.frame.initialize(repeating: 0, count: size)
		self.real.initialize(repeating: 0, count: size / 2)
		self.imaginary.initialize(repeating: 0, count: size / 2)
		self.magnitudes.initialize(repeating: 0, count: size / 2)
		self.levels.initialize(repeating: 0, count: EQScale.spectrumPointCount)
		self.ranges = self.makeRanges()
	}

	deinit {
		vDSP_destroy_fftsetup(self.setup)
		self.window.deallocate()
		self.ring.deallocate()
		self.frame.deallocate()
		self.real.deallocate()
		self.imaginary.deallocate()
		self.magnitudes.deallocate()
		self.levels.deallocate()
	}

	/// Maps every display point to the FFT bins it covers.
	private func makeRanges() -> [PointRange] {
		let binWidth = self.sampleRate / Float(SpectrumAnalyzer.size)
		let lastBin = SpectrumAnalyzer.size / 2 - 1
		let count = EQScale.spectrumPointCount

		return (0..<count).map { index in
			let lowFrequency = EQScale.frequency(at: Float(index) / Float(count))
			let highFrequency = EQScale.frequency(at: Float(index + 1) / Float(count))
			let centerFrequency = (lowFrequency * highFrequency).squareRoot()
			let tilt = 3 * log2(centerFrequency / 500)

			let lowBin = lowFrequency / binWidth
			let highBin = highFrequency / binWidth

			if highBin - lowBin < 1 {
				let lower = min(max(Int(lowBin.rounded(.down)), 1), lastBin)
				let upper = min(lower + 1, lastBin)
				let center = (lowBin + highBin) / 2
				return PointRange(low: lower, high: upper, fraction: min(max(center - Float(lower), 0), 1), interpolates: true, tilt: tilt)
			}
			let lower = min(max(Int(lowBin.rounded(.up)), 1), lastBin)
			let upper = min(max(Int(highBin.rounded(.down)), lower), lastBin)
			return PointRange(low: lower, high: upper, fraction: 0, interpolates: false, tilt: tilt)
		}
	}

	/// Audio thread. Mixes the buffer to mono, and once enough new samples arrived, publishes a fresh spectrum.
	func feed(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, channels: Int, isInterleaved: Bool) {
		let buffers = UnsafeMutableAudioBufferListPointer(list)
		guard frames > 0, let first = buffers.first, let firstData = first.mData else { return }
		let size = SpectrumAnalyzer.size
		let firstSamples = firstData.assumingMemoryBound(to: Float.self)

		if isInterleaved {
			let stride = max(channels, 1)
			for frameIndex in 0..<frames {
				var sum: Float = 0
				for channel in 0..<stride {
					sum += firstSamples[frameIndex * stride + channel]
				}
				self.ring[self.writeIndex] = sum / Float(stride)
				self.writeIndex = (self.writeIndex + 1) & (size - 1)
			}
		} else {
			let secondSamples = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
			for frameIndex in 0..<frames {
				let sample = secondSamples.map { (firstSamples[frameIndex] + $0[frameIndex]) * 0.5 } ?? firstSamples[frameIndex]
				self.ring[self.writeIndex] = sample
				self.writeIndex = (self.writeIndex + 1) & (size - 1)
			}
		}

		self.sinceLastTransform += frames
		if self.sinceLastTransform >= SpectrumAnalyzer.hop {
			self.sinceLastTransform = 0
			self.transform()
			SpectrumStore.shared.publish(self.levels)
		}
	}

	private func transform() {
		let size = SpectrumAnalyzer.size
		let half = size / 2

		// oldest sample first: the ring's write head is where the oldest one sits
		let tail = size - self.writeIndex
		self.frame.update(from: self.ring + self.writeIndex, count: tail)
		(self.frame + tail).update(from: self.ring, count: self.writeIndex)
		vDSP_vmul(self.frame, 1, self.window, 1, self.frame, 1, vDSP_Length(size))

		var split = DSPSplitComplex(realp: self.real, imagp: self.imaginary)
		self.frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
			vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
		}
		vDSP_fft_zrip(self.setup, &split, 1, SpectrumAnalyzer.log2Size, FFTDirection(FFT_FORWARD))
		vDSP_zvabs(&split, 1, self.magnitudes, 1, vDSP_Length(half))

		// vDSP's real FFT is 2x the textbook DFT and the normalized Hann window halves a sine's peak: a
		// full-scale sine reads `size / 2`, so `2 / size` brings the magnitudes back to amplitude (1.0 = 0 dBFS).
		let scale = 2 / Float(size)
		let span = SpectrumAnalyzer.ceilingDecibels - SpectrumAnalyzer.floorDecibels

		for index in 0..<EQScale.spectrumPointCount {
			let range = self.ranges[index]
			var magnitude: Float
			if range.interpolates {
				magnitude = self.magnitudes[range.low] * (1 - range.fraction) + self.magnitudes[range.high] * range.fraction
			} else {
				magnitude = 0
				for bin in range.low...range.high {
					magnitude = max(magnitude, self.magnitudes[bin])
				}
			}
			let decibels = 20 * log10f(max(magnitude * scale, 1e-9)) + range.tilt
			self.levels[index] = min(max((decibels - SpectrumAnalyzer.floorDecibels) / span, 0), 1)
		}
	}
}
