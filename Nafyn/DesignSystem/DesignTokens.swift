// Made by Lumaa

import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

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

/// Every token below re-reads `ThemeManager.shared.current` on each access rather than caching a value,
/// so views that read these tokens in `body` re-theme automatically when the user switches theme in
/// Settings (same Observation-tracking pattern as `PlayerEngine.shared`/`Navigator.shared`).
enum DTColor {
	private static var isSystemTheme: Bool { ThemeManager.shared.current == .system }

	static var background: Color {
		isSystemTheme ? Color(uiColor: .systemGroupedBackground) : Color(hex: "2A2A27")
	}
	static var textPrimary: Color {
		isSystemTheme ? Color.primary : Color.white.opacity(0.68)
	}
	static var surfaceInput: Color {
		isSystemTheme ? Color(uiColor: .secondarySystemGroupedBackground) : Color.black.opacity(0.31)
	}
	static var surfaceSelect: Color {
		isSystemTheme ? Color(uiColor: .secondarySystemGroupedBackground) : Color(hex: "1A1A1A")
	}
	static var surfaceSelectHover: Color {
		isSystemTheme ? Color(uiColor: .tertiarySystemGroupedBackground) : Color(hex: "232323")
	}
	static var borderSelect: Color {
		isSystemTheme ? Color(uiColor: .separator) : Color(hex: "333333")
	}
	static var buttonFilled: Color {
		isSystemTheme ? Color.accentColor : Color.white.opacity(0.68)
	}
	static var buttonFilledHover: Color {
		isSystemTheme ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.82)
	}
	static var buttonDanger: Color {
		isSystemTheme ? Color.red : Color(hex: "E06666", opacity: 0.68)
	}
	static var buttonDangerHover: Color {
		isSystemTheme ? Color.red.opacity(0.85) : Color(hex: "E06666", opacity: 0.82)
	}
	static var accentStart: Color {
		isSystemTheme ? Color.accentColor.opacity(0.5) : Color(hex: "2E74FF", opacity: 0.5)
	}
	static var accentEnd: Color {
		isSystemTheme ? Color.accentColor.opacity(0.2) : Color(hex: "1F6AFF", opacity: 0.2)
	}

	/// A genuine shaded gradient (varies luminance/saturation), not a same-hue opacity fade — see the
	/// chart-gradient rule in CLAUDE.md. Used for `Chart` marks, distinct from `accentStart`/`accentEnd`
	/// which are plain UI tint colors used elsewhere at reduced opacity.
	static var accentGradient: AnyGradient {
		isSystemTheme ? Color.accentColor.gradient : Color(hex: "2E74FF").gradient
	}

	static var statusWaiting: Color { isSystemTheme ? Color.yellow : Color(hex: "E0C666") }
	static var statusActive: Color { isSystemTheme ? Color.orange : Color(hex: "E0A666") }
	static var statusSuccess: Color { isSystemTheme ? Color.green : Color(hex: "66E086") }
	static var statusFailure: Color { isSystemTheme ? Color.red : Color(hex: "E06666") }
}

enum DTFont {
	private static var isSystemTheme: Bool { ThemeManager.shared.current == .system }

	public static func serif(_ size: CGFloat) -> Font {
		isSystemTheme ? .system(size: size - 5) : .custom("InstrumentSerif-Regular", size: size)
	}

	public static func serifItalic(_ size: CGFloat) -> Font {
		isSystemTheme ? .system(size: size - 5) : .custom("InstrumentSerif-Italic", size: size)
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
