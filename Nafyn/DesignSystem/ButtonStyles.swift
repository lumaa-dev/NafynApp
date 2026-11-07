// Made by Lumaa

import SwiftUI

/// A disabled button is at 174/255 opacity (DESIGN.md "Buttons"); the colours of a filled / hollow button already
/// carry 174 themselves, so the two stack on top of each other (118/255 in all).
private let disabledButtonOpacity: Double = 174.0 / 255.0

struct FilledButtonStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled
	var style: NafynButtonStyle = .normal

	var danger: Bool { self.style == .danger }

	func makeBody(configuration: Configuration) -> some View {
		let base = danger ? DTColor.buttonDanger : DTColor.buttonFilled
		let hover = danger ? DTColor.buttonDangerHover : DTColor.buttonFilledHover

		configuration.label
			.font(DTFont.serif(20))
			.foregroundStyle(danger ? Color.white : .black)
			.lineLimit(1)
			.minimumScaleFactor(0.7)
			.truncationMode(.tail)
			.multilineTextAlignment(.center)
			.padding(.vertical, DTSpacing.buttonVertical)
			.padding(.horizontal, DTSpacing.buttonHorizontal)
			.background(configuration.isPressed ? hover : base, in: Capsule())
			.overlay(Capsule().strokeBorder(configuration.isPressed ? hover : base, lineWidth: 1))
			.opacity(self.isEnabled ? 1 : disabledButtonOpacity)
			.animation(DTMotion.buttonHover, value: configuration.isPressed)
			.animation(DTMotion.buttonHover, value: self.isEnabled)
	}
}

struct HollowButtonStyle: ButtonStyle {
	@Environment(\.isEnabled) private var isEnabled
	var style: NafynButtonStyle = .normal

	var danger: Bool { self.style == .danger }

	func makeBody(configuration: Configuration) -> some View {
		let base = danger ? DTColor.dangerText : DTColor.buttonFilled
		let hover = danger ? DTColor.dangerText : DTColor.buttonFilledHover

		configuration.label
			.font(DTFont.serif(20))
			.foregroundStyle(danger ? DTColor.dangerText : DTColor.textPrimary)
			.lineLimit(1)
			.minimumScaleFactor(0.7)
			.truncationMode(.tail)
			.multilineTextAlignment(.center)
			.padding(.vertical, DTSpacing.buttonVertical)
			.padding(.horizontal, DTSpacing.buttonHorizontal)
			// a hollow destructive button stays hollow when pressed: a faint wash of the red, nothing fills
			.background(Capsule().fill(danger && configuration.isPressed ? DTColor.dangerText.opacity(0.2) : .clear))
			.overlay(Capsule().strokeBorder(configuration.isPressed ? hover : base, lineWidth: 1))
			.opacity(self.isEnabled ? 1 : disabledButtonOpacity)
			.animation(DTMotion.buttonHover, value: configuration.isPressed)
			.animation(DTMotion.buttonHover, value: self.isEnabled)
	}
}

extension ButtonStyle where Self == FilledButtonStyle {
	static func filled(_ style: NafynButtonStyle = .normal) -> FilledButtonStyle { return FilledButtonStyle(style: style) }
}

extension ButtonStyle where Self == HollowButtonStyle {
	static func hollow(_ style: NafynButtonStyle = .normal) -> HollowButtonStyle { return HollowButtonStyle(style: style) }
}

enum NafynButtonStyle {
	case normal
	case danger
}
