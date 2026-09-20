// Made by Lumaa

import SwiftUI

struct FilledButtonStyle: ButtonStyle {
	var style: NafynButtonStyle = .normal

	var danger: Bool { self.style == .danger }

	func makeBody(configuration: Configuration) -> some View {
		let base = danger ? DTColor.buttonDanger : DTColor.buttonFilled
		let hover = danger ? DTColor.buttonDangerHover : DTColor.buttonFilledHover

		configuration.label
			.font(DTFont.serif(20))
			.foregroundStyle(danger ? DTColor.textPrimary : .black)
			.lineLimit(1)
			.truncationMode(.tail)
			.padding(.vertical, DTSpacing.buttonVertical)
			.padding(.horizontal, DTSpacing.buttonHorizontal)
			.background(configuration.isPressed ? hover : base, in: Capsule())
			.overlay(Capsule().strokeBorder(configuration.isPressed ? hover : base, lineWidth: 1))
			.animation(DTMotion.buttonHover, value: configuration.isPressed)
	}
}

struct HollowButtonStyle: ButtonStyle {
	var style: NafynButtonStyle = .normal

	var danger: Bool { self.style == .danger }

	func makeBody(configuration: Configuration) -> some View {
		let base = danger ? DTColor.buttonDanger : DTColor.buttonFilled
		let hover = danger ? DTColor.buttonDangerHover : DTColor.buttonFilledHover

		configuration.label
			.font(DTFont.serif(20))
			.foregroundStyle(DTColor.textPrimary)
			.lineLimit(1)
			.truncationMode(.tail)
			.padding(.vertical, DTSpacing.buttonVertical)
			.padding(.horizontal, DTSpacing.buttonHorizontal)
			.background(Capsule().fill(.clear))
			.overlay(Capsule().strokeBorder(configuration.isPressed ? hover : base, lineWidth: 1))
			.animation(DTMotion.buttonHover, value: configuration.isPressed)
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
