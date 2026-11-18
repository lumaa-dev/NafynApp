// Made by Lumaa

import Foundation

/// The user's equalizer: one gain per band (``EQScale/bandFrequencies``), an on/off switch, and the presets.
/// Local to the device, saved the moment anything changes and pushed straight to the audio through
/// ``EqualizerRegistry``. The audio side is ``EqualizerProcessor``, which `AudioReactivityEngine`'s tap runs.
///
/// Only the audio this device plays is shaped: while another device is the Nafyn Unity master the sound comes
/// out of that device (see `PlaybackSource.isEqualizerApplicable`).
@Observable
final class EqualizerEngine {
	static let shared = EqualizerEngine()

	/// Range of every band, in dB.
	static let gainRange: ClosedRange<Double> = -12...12

	private static let gainsKey = "app.eq.gains"
	private static let enabledKey = "app.eq.enabled"

	struct Preset: Identifiable {
		let id: String
		let name: LocalizedStringResource
		let gains: [Double]
	}

	/// One value per band of ``EQScale/bandFrequencies``: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz.
	static let presets: [Preset] = [
		Preset(id: "flat", name: "eq-preset-flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
		Preset(id: "bass-booster", name: "eq-preset-bass-booster", gains: [6, 5, 4, 2, 1, 0, 0, 0, 0, 0]),
		Preset(id: "bass-reducer", name: "eq-preset-bass-reducer", gains: [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0]),
		Preset(id: "treble-booster", name: "eq-preset-treble-booster", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
		Preset(id: "treble-reducer", name: "eq-preset-treble-reducer", gains: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]),
		Preset(id: "vocal", name: "eq-preset-vocal", gains: [-2, -2, -1, 0, 2, 4, 4, 3, 1, 0]),
		Preset(id: "acoustic", name: "eq-preset-acoustic", gains: [4, 4, 3, 1, 1, 1, 2, 3, 3, 2]),
		Preset(id: "rock", name: "eq-preset-rock", gains: [5, 4, 2, -1, -2, -1, 2, 4, 5, 5]),
		Preset(id: "pop", name: "eq-preset-pop", gains: [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2]),
		Preset(id: "jazz", name: "eq-preset-jazz", gains: [3, 2, 1, 2, -2, -2, 0, 1, 2, 3]),
		Preset(id: "electronic", name: "eq-preset-electronic", gains: [5, 4, 1, 0, -2, 2, 1, 2, 4, 5]),
		Preset(id: "hip-hop", name: "eq-preset-hip-hop", gains: [6, 5, 2, 3, -1, -1, 2, 0, 3, 4]),
	]

	/// Current gain of each band, in dB. Changes every frame while a reset or a preset glides in.
	private(set) var gains: [Double]

	var isEnabled: Bool {
		didSet {
			guard oldValue != self.isEnabled else { return }
			UserDefaults.standard.set(self.isEnabled, forKey: Self.enabledKey)
			self.push()
		}
	}

	@ObservationIgnored private var rampTask: Task<Void, Never>?

	private init() {
		let stored = UserDefaults.standard.array(forKey: Self.gainsKey) as? [Double]
		if let stored, stored.count == EQScale.bandCount {
			self.gains = stored.map { min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound) }
		} else {
			self.gains = Array(repeating: 0, count: EQScale.bandCount)
		}
		self.isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
		self.push()
	}

	/// Every band is at 0 dB.
	var isFlat: Bool {
		self.gains.allSatisfy { abs($0) < 0.01 }
	}

	/// The preset the current gains match, if any.
	var activePreset: Preset? {
		Self.presets.first { preset in
			zip(preset.gains, self.gains).allSatisfy { abs($0 - $1) < 0.05 }
		}
	}

	/// Moves one band right now (a slider being dragged), cancelling any glide in progress.
	func setGain(_ value: Double, at index: Int) {
		guard self.gains.indices.contains(index) else { return }
		self.rampTask?.cancel()
		self.gains[index] = min(max(value, Self.gainRange.lowerBound), Self.gainRange.upperBound)
		self.persist()
		self.push()
	}

	/// Glides every band back to 0 dB.
	func reset() {
		self.animate(to: Array(repeating: 0, count: EQScale.bandCount))
	}

	func apply(_ preset: Preset) {
		self.animate(to: preset.gains)
	}

	/// Eases every band toward `target`. The gains are updated every frame, so the audio, the curve and the
	/// sliders all glide together; the result is saved once it lands.
	private func animate(to target: [Double], duration: TimeInterval = 0.4) {
		guard target.count == self.gains.count else { return }
		self.rampTask?.cancel()

		let start = self.gains
		self.rampTask = Task { @MainActor [weak self] in
			let began = CFAbsoluteTimeGetCurrent()
			while !Task.isCancelled {
				guard let self else { return }
				let progress = min((CFAbsoluteTimeGetCurrent() - began) / duration, 1)
				let eased = 1 - pow(1 - progress, 3)
				self.gains = zip(start, target).map { $0 + ($1 - $0) * eased }
				self.push()
				if progress >= 1 { break }
				try? await Task.sleep(for: .milliseconds(16))
			}
			guard !Task.isCancelled else { return }
			self?.persist()
		}
	}

	private func persist() {
		UserDefaults.standard.set(self.gains, forKey: Self.gainsKey)
	}

	private func push() {
		EqualizerRegistry.shared.update(gains: self.gains, enabled: self.isEnabled)
	}
}
