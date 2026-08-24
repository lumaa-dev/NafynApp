// Made by Lumaa

import SwiftUI
import CoreText

extension Color {
	init(hex: String, opacity: Double = 1) {
		let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
		var value: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&value)
		let r = Double((value >> 16) & 0xFF) / 255
		let g = Double((value >> 8) & 0xFF) / 255
		let b = Double(value & 0xFF) / 255
		self.init(red: r, green: g, blue: b, opacity: opacity)
	}
}

enum DTColor {
	static let background = Color(hex: "2A2A27")
	static let textPrimary = Color.white.opacity(0.68)
	static let surfaceInput = Color.black.opacity(0.31)
	static let surfaceSelect = Color(hex: "1A1A1A")
	static let surfaceSelectHover = Color(hex: "232323")
	static let borderSelect = Color(hex: "333333")
	static let buttonFilled = Color.white.opacity(0.68)
	static let buttonFilledHover = Color.white.opacity(0.82)
	static let buttonDanger = Color(hex: "E06666", opacity: 0.68)
	static let buttonDangerHover = Color(hex: "E06666", opacity: 0.82)
	static let accentStart = Color(hex: "2E74FF", opacity: 0.5)
	static let accentEnd = Color(hex: "1F6AFF", opacity: 0.2)

	static let accentGradient = LinearGradient(
		colors: [accentStart, accentEnd],
		startPoint: .top,
		endPoint: .bottom
	)

	static let statusWaiting = Color(hex: "E0C666")
	static let statusActive = Color(hex: "E0A666")
	static let statusSuccess = Color(hex: "66E086")
	static let statusFailure = Color(hex: "E06666")
}

enum DTFont {
	public static func serif(_ size: CGFloat) -> Font {
		.custom("InstrumentSerif-Regular", size: size)
	}

	public static func serifItalic(_ size: CGFloat) -> Font {
		.custom("InstrumentSerif-Italic", size: size)
	}

	public static func system(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, width: Font.Width = .standard) -> Font {
		return .system(size: size, weight: weight, design: design).width(width)
	}
}

enum DTRadius {
	static let pill: CGFloat = 999
	static let textArea: CGFloat = 20
}

enum DTSpacing {
	static let inputVertical: CGFloat = 15
	static let inputHorizontal: CGFloat = 30
	static let buttonVertical: CGFloat = 12
	static let buttonHorizontal: CGFloat = 48
}

enum DTMotion {
	static let sidebar = Animation.easeOut(duration: 0.25)
	static let buttonHover = Animation.easeOut(duration: 0.15)
	static let toast = Animation.easeOut(duration: 0.35)
}

enum DTFontRegistration {
	static func registerCustomFonts() {
		for name in ["InstrumentSerif-Regular", "InstrumentSerif-Italic"] {
			guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
			CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
		}
	}
}
