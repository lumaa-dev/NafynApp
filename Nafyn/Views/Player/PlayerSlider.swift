// Made by Lumaa

import SwiftUI

/// Renamed port of `CiderSlider` (Cider's now-playing scrubber) — behavior left unchanged.
struct PlayerSlider: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

	@Binding var value: Float
	var range: ClosedRange<Float>

	@Binding var isDragging: Bool
	var onEditingChanged: () -> Void = {}

	@State private var lastDragValue: Float? = nil
	@State private var initDragValue: Float? = nil

	init(
		_ value: Binding<Float>,
		range: ClosedRange<Float>,
		isDragging: Binding<Bool> = .constant(false),
		onEditingChanged: @escaping () -> Void = {}
	) {
		self._value = value
		self.range = range
		self._isDragging = isDragging
		self.onEditingChanged = onEditingChanged
	}

	var body: some View {
		let expandedSliderHeight: CGFloat = 20
		let sliderHeight: CGFloat = isDragging ? expandedSliderHeight : 8
		let val: CGFloat = CGFloat((self.value - self.range.lowerBound) / (self.range.upperBound - self.range.lowerBound) + range.lowerBound)

		GeometryReader { proxy in
			let size: CGSize = proxy.size

			ZStack {
				ZStack(alignment: .leading) {
					Rectangle()
						.fill(Color.white)
						.frame(
							width: min(val, 1.0) * size.width,
							height: sliderHeight,
							alignment: .leading
						)
						.zIndex(20)

					Rectangle()
						.fill(Color.gray.opacity(0.7))
						.frame(width: size.width, height: sliderHeight, alignment: .leading)
						.zIndex(1)
				}
				.clipShape(Capsule(style: .continuous))
				.frame(height: sliderHeight, alignment: .center)
				.scaleEffect(self.isDragging ? 1.02 : 1.0, anchor: .center)
			}
			.frame(width: size.width, height: size.height, alignment: .center)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { gestureValue in
						withAnimation(.interactiveSpring(duration: 0.35)) {
							isDragging = true
						}

						if initDragValue == nil {
							self.initDragValue = self.value
						}

						let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Float(gestureValue.translation.width / size.width) + self.initDragValue!
						value = max(range.lowerBound, min(range.upperBound, newValue))

						lastDragValue = newValue
					}
					.onEnded { _ in
						withAnimation(.interactiveSpring(duration: reduceMotion ? 0.0 : 0.35)) {
							isDragging = false
						}
						lastDragValue = nil
						initDragValue = nil
						onEditingChanged()
					}
			)
		}
	}
}
