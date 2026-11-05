// Made by Lumaa

import SwiftUI

/// One band of the equalizer: a vertical slider whose thumb is a plain circle at rest and morphs into a
/// Liquid Glass sphere while held. Its range is `EqualizerEngine.gainRange`, and it is magnetic around 0 dB:
/// a drag close to flat pulls into it and ticks when it lands.
///
/// It fills the height it is given and maps gains with ``EQGeometry``, so its thumb sits exactly on the
/// ``EQVisualizer`` curve drawn in the same space.
struct EQBandSlider: View {
	let frequency: Float
	let gain: Double
	let onChange: (Double) -> Void

	/// Gains within this many dB of flat snap to exactly 0 dB...
	private static let stickyZone = 0.6
	/// ...and up to this far they are pulled toward it, fading back to the finger's own value.
	private static let magneticZone = 1.8

	private static let restingSize: CGFloat = 20
	private static let heldSize: CGFloat = 40

	@GestureState private var isHeld = false
	/// Distance between where the finger landed and the thumb's center, so grabbing the thumb never makes it jump.
	@State private var grabOffset: CGFloat?
	@State private var zeroTick = 0

	var body: some View {
		GeometryReader { proxy in
			let height = proxy.size.height
			let centerX = proxy.size.width / 2
			let thumbY = EQGeometry.y(for: self.gain, height: height)

			ZStack {
				self.track(centerX: centerX, height: height, thumbY: thumbY)

				EQBandThumb(isHeld: self.isHeld, tint: EQGradient.color(at: Double(EQScale.position(of: self.frequency))))
					.position(x: centerX, y: thumbY)
			}
			.contentShape(Rectangle())
			.gesture(self.drag(height: height, thumbY: thumbY))
		}
		.sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.9), trigger: self.zeroTick)
		.accessibilityElement()
		.accessibilityLabel("\(Self.label(for: self.frequency)) Hz")
		.accessibilityValue("\(self.gain.formatted(.number.precision(.fractionLength(1)))) dB")
		.accessibilityAdjustableAction { direction in
			let step = direction == .increment ? 1.0 : -1.0
			self.onChange(min(max((self.gain + step).rounded(), EqualizerEngine.gainRange.lowerBound), EqualizerEngine.gainRange.upperBound))
		}
	}

	/// A hairline from -12 to +12 dB, lit between 0 dB and the thumb.
	private func track(centerX: CGFloat, height: CGFloat, thumbY: CGFloat) -> some View {
		let zeroY = EQGeometry.y(for: 0, height: height)
		return ZStack {
			Capsule()
				.fill(Color.white.opacity(0.10))
				.frame(width: 3, height: height - EQGeometry.verticalInset * 2 + 6)
				.position(x: centerX, y: height / 2)
			Capsule()
				.fill(Color.white.opacity(0.35))
				.frame(width: 3, height: max(abs(thumbY - zeroY), 0.5))
				.position(x: centerX, y: (thumbY + zeroY) / 2)
			// the 0 dB notch the magnet pulls toward
			Capsule()
				.fill(Color.white.opacity(0.5))
				.frame(width: 11, height: 2)
				.position(x: centerX, y: zeroY)
		}
	}

	private func drag(height: CGFloat, thumbY: CGFloat) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.updating(self.$isHeld) { _, isHeld, _ in
				isHeld = true
			}
			.onChanged { value in
				if self.grabOffset == nil {
					// landing on the thumb keeps it under the finger; landing elsewhere on the track moves it there
					let landed = value.startLocation.y - thumbY
					self.grabOffset = abs(landed) <= Self.heldSize / 2 ? landed : 0
				}
				let offset = self.grabOffset ?? 0

				let raw = EQGeometry.gain(forY: value.location.y - offset, height: height)
				let pulled = (Self.magnetized(raw) * 10).rounded() / 10
				guard pulled != self.gain else { return }

				if pulled == 0 {
					self.zeroTick += 1
				}
				self.onChange(pulled)
			}
			.onEnded { _ in
				self.grabOffset = nil
			}
	}

	/// 0 dB holds the value flat inside the sticky zone, then eases back to the finger's own value across
	/// the magnetic zone; the mapping is continuous, so nothing jumps when the finger leaves it.
	static func magnetized(_ value: Double) -> Double {
		let magnitude = abs(value)
		guard magnitude < self.magneticZone else { return value }
		guard magnitude > self.stickyZone else { return 0 }
		let slope = self.magneticZone / (self.magneticZone - self.stickyZone)
		return (value < 0 ? -1 : 1) * (magnitude - self.stickyZone) * slope
	}

	/// "32", "1k", "16k": short enough for a column of a phone-wide panel.
	static func label(for frequency: Float) -> String {
		frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
	}
}

/// The thumb. At rest: a clean white circle. Held: it grows and the white dissolves into a Liquid Glass
/// sphere that magnifies the curve under it. One view with changing properties, so SwiftUI morphs rather than swaps.
private struct EQBandThumb: View {
	let isHeld: Bool
	let tint: Color

	var body: some View {
		let size = self.isHeld ? 40.0 : 20.0
		GlassEffectContainer {
			Circle()
				.fill(Color.white)
				.opacity(self.isHeld ? 0 : 1)
				.frame(width: size, height: size)
				.glassEffect(self.isHeld ? .regular.tint(self.tint.opacity(0.25)) : .identity, in: .circle)
		}
		.frame(width: 40, height: 40)
		.shadow(color: .black.opacity(self.isHeld ? 0.3 : 0.4), radius: self.isHeld ? 12 : 3, y: self.isHeld ? 6 : 1)
		.animation(.spring(response: 0.38, dampingFraction: 0.62), value: self.isHeld)
	}
}
