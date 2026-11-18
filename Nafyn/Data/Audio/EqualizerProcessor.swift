// Made by Lumaa

import AVFoundation
import AudioToolbox
import Synchronization
import os

/// One playing item's equalizer: an `AVAudioEngine` running in *real-time manual rendering* mode
/// (`inputNode → AVAudioUnitEQ → mainMixerNode`), driven buffer by buffer from the `MTAudioProcessingTap` that
/// `AudioReactivityEngine` already puts on the `AVPlayer` item. The tap hands its samples to the engine
/// through `inputNode`'s input block, the engine renders them through the EQ, and the result is written back
/// over the tap's buffer, so the sound that reaches the speaker is the equalized one. No hardware is touched.
///
/// The spectrum analyzer listens to what comes *out* of the EQ, so the visualizer shows the sound you hear.
///
/// Everything here runs on the audio thread except ``apply(gains:enabled:)``, which the main thread calls.
nonisolated final class EqualizerProcessor {
	/// Bandwidth of each parametric band, in octaves: bands are an octave apart, so neighbors blend smoothly.
	private static let bandwidth: Float = 1

	private let channels: Int
	private let isInterleaved: Bool
	private let maxFrames: Int
	private let analyzer: SpectrumAnalyzer?

	private var engine: AVAudioEngine?
	private var equalizer: AVAudioUnitEQ?
	private var renderBlock: AVAudioEngineManualRenderingBlock?
	/// Rendered samples, in the engine's own (standard, deinterleaved) format.
	private var output: AVAudioPCMBuffer?
	/// Only when the tap is interleaved: the tap's samples deinterleaved for the engine.
	private var scratch: AVAudioPCMBuffer?

	/// The buffer list `inputNode` reads on its next pull; set around each render call.
	nonisolated(unsafe) private var pendingInput: UnsafePointer<AudioBufferList>?
	/// Whether buffers go through the EQ. Off when the equalizer is disabled or every band sits at 0 dB, so
	/// the sound is then bit-for-bit untouched.
	private let isShaping = Atomic<Bool>(false)

	/// `nil` when the tap's format isn't 32-bit float PCM in one or two channels, which `AVPlayer` always
	/// delivers in practice.
	init?(description: AudioStreamBasicDescription, maxFrames: Int) {
		guard description.mFormatID == kAudioFormatLinearPCM,
			  description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
			  description.mBitsPerChannel == 32,
			  description.mSampleRate > 0,
			  (1...2).contains(Int(description.mChannelsPerFrame)),
			  maxFrames > 0
		else { return nil }

		self.channels = Int(description.mChannelsPerFrame)
		self.isInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 && self.channels > 1
		self.maxFrames = maxFrames
		self.analyzer = SpectrumAnalyzer(sampleRate: description.mSampleRate)

		self.configureEngine(sampleRate: description.mSampleRate)
		EqualizerRegistry.shared.register(self)
	}

	deinit {
		self.engine?.stop()
	}

	private func configureEngine(sampleRate: Double) {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(self.channels)) else { return }
		let capacity = AVAudioFrameCount(self.maxFrames)

		let engine = AVAudioEngine()
		do {
			try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: capacity)
		} catch {
			return
		}

		let equalizer = AVAudioUnitEQ(numberOfBands: EQScale.bandCount)
		for (index, band) in equalizer.bands.enumerated() {
			band.filterType = .parametric
			band.frequency = EQScale.bandFrequencies[index]
			band.bandwidth = EqualizerProcessor.bandwidth
			band.gain = 0
			band.bypass = false
		}

		engine.attach(equalizer)
		do {
			// the throwing iOS 27 variant: a refused connection is an error here, not an Objective-C exception
			try engine.connectNode(engine.inputNode, to: equalizer, fromBus: 0, toBus: 0, format: format)
			try engine.connectNode(equalizer, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: format)
		} catch {
			return
		}
		_ = engine.inputNode.setManualRenderingInputPCMFormat(format) { [unowned self] _ in
			self.pendingInput
		}

		guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
		output.frameLength = capacity
		if self.isInterleaved {
			guard let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
			scratch.frameLength = capacity
			self.scratch = scratch
		}

		do {
			try engine.start()
		} catch {
			return
		}

		self.engine = engine
		self.equalizer = equalizer
		self.output = output
		self.renderBlock = engine.manualRenderingBlock
	}

	/// Main thread (or the thread that registers the processor). Parameter changes are thread-safe on an
	/// `AUAudioUnit`, so this never has to wait for the audio thread.
	func apply(gains: [Double], enabled: Bool) {
		guard let equalizer else { return }
		let isFlat = gains.allSatisfy { abs($0) < 0.01 }

		for (index, band) in equalizer.bands.enumerated() where index < gains.count {
			band.gain = Float(gains[index])
		}
		// Boosting raises the peaks, and a float signal above 1.0 clips at the converter: take half the
		// loudest boost back so +12 dB of bass doesn't distort.
		equalizer.globalGain = -Float(max(0, gains.max() ?? 0)) / 2
		self.isShaping.store(enabled && !isFlat, ordering: .relaxed)
	}

	/// Audio thread. Equalizes `list` in place, then feeds what comes out to the spectrum analyzer.
	func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
		guard frames > 0 else { return }

		if self.isShaping.load(ordering: .relaxed), frames <= self.maxFrames, let renderBlock, let output {
			self.render(list, frames: frames, through: renderBlock, into: output)
		}
		self.analyzer?.feed(list, frames: frames, channels: self.channels, isInterleaved: self.isInterleaved)
	}

	private func render(
		_ list: UnsafeMutablePointer<AudioBufferList>,
		frames: Int,
		through renderBlock: AVAudioEngineManualRenderingBlock,
		into output: AVAudioPCMBuffer
	) {
		if let scratch = self.scratch {
			self.deinterleave(list, frames: frames, into: scratch)
			self.pendingInput = UnsafePointer(scratch.audioBufferList)
		} else {
			self.pendingInput = UnsafePointer(list)
		}

		// The engine shrinks `mDataByteSize` to what it rendered: give it the full size back each time.
		let outputList = output.mutableAudioBufferList
		let byteSize = UInt32(frames * MemoryLayout<Float>.size)
		let outputBuffers = UnsafeMutableAudioBufferListPointer(outputList)
		for index in outputBuffers.indices {
			outputBuffers[index].mDataByteSize = byteSize
		}

		var status: OSStatus = noErr
		let result = renderBlock(AVAudioFrameCount(frames), outputList, &status)
		self.pendingInput = nil
		guard result == .success, let channelData = output.floatChannelData else { return }

		let destination = UnsafeMutableAudioBufferListPointer(list)
		if self.isInterleaved {
			guard let interleaved = destination.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
			for channel in 0..<self.channels {
				for frame in 0..<frames {
					interleaved[frame * self.channels + channel] = channelData[channel][frame]
				}
			}
		} else {
			for channel in 0..<min(destination.count, self.channels) {
				guard let data = destination[channel].mData else { continue }
				memcpy(data, channelData[channel], frames * MemoryLayout<Float>.size)
			}
		}
	}

	private func deinterleave(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, into scratch: AVAudioPCMBuffer) {
		guard let source = UnsafeMutableAudioBufferListPointer(list).first?.mData?.assumingMemoryBound(to: Float.self),
			  let channelData = scratch.floatChannelData
		else { return }
		let outputList = UnsafeMutableAudioBufferListPointer(scratch.mutableAudioBufferList)
		for index in outputList.indices {
			outputList[index].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
		}
		for channel in 0..<self.channels {
			for frame in 0..<frames {
				channelData[channel][frame] = source[frame * self.channels + channel]
			}
		}
	}
}

/// Knows the current band gains and every live ``EqualizerProcessor`` (one per playing item), so a slider
/// moved on the main thread reaches the audio immediately and a processor created mid-song starts out with
/// the right settings. Weak references: the tap owns its processor.
nonisolated final class EqualizerRegistry: @unchecked Sendable {
	static let shared = EqualizerRegistry()

	private struct Live {
		var gains = [Double](repeating: 0, count: EQScale.bandCount)
		var enabled = true
	}

	private final class Weak {
		weak var processor: EqualizerProcessor?
		init(_ processor: EqualizerProcessor) { self.processor = processor }
	}

	private let live = OSAllocatedUnfairLock(initialState: Live())
	private let processors = OSAllocatedUnfairLock(initialState: [Weak]())

	func update(gains: [Double], enabled: Bool) {
		self.live.withLock {
			$0.gains = gains
			$0.enabled = enabled
		}
		let current = self.processors.withLock { list -> [EqualizerProcessor] in
			list.removeAll { $0.processor == nil }
			return list.compactMap(\.processor)
		}
		for processor in current {
			processor.apply(gains: gains, enabled: enabled)
		}
	}

	fileprivate func register(_ processor: EqualizerProcessor) {
		let snapshot = self.live.withLock { $0 }
		processor.apply(gains: snapshot.gains, enabled: snapshot.enabled)
		self.processors.withLock { $0.append(Weak(processor)) }
	}
}
