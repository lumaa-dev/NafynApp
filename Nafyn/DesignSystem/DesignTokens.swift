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

/// Per-device font choices, kept in `UserDefaults` (not on the server): the OpenDyslexic switch.
@Observable
final class FontPreferences {
	static let shared = FontPreferences()

	private static let dyslexicKey = "app.useOpenDyslexic"

	/// Sets every text of the app in OpenDyslexic, in place of Instrument Serif and the system font.
	var useDyslexic: Bool {
		didSet {
			guard oldValue != self.useDyslexic else { return }
			UserDefaults.standard.set(self.useDyslexic, forKey: Self.dyslexicKey)
			AppAppearance.configureNavigationBar()
		}
	}

	private init() {
		self.useDyslexic = UserDefaults.standard.bool(forKey: Self.dyslexicKey)
	}
}

/// Every font scales with the user's Dynamic Type setting: a point size is mapped to the closest system
/// text style, and that style drives the scaling (`Font.custom(_:size:relativeTo:)` for Instrument Serif,
/// the style's own font for the system theme). Sizes therefore stay as design-time "base" sizes at the
/// default content size, and grow/shrink with the accessibility setting.
///
/// With ``FontPreferences/useDyslexic`` on, every token below answers with OpenDyslexic instead, whatever the
/// theme. OpenDyslexic sets much larger than the fonts the sizes were drawn for, so its sizes are shrunk by
/// ``dyslexicScale`` to keep rows and buttons from clipping.
enum DTFont {
	private static var isSystemTheme: Bool { ThemeManager.shared.current == .system }
	private static var isDyslexic: Bool { FontPreferences.shared.useDyslexic }

	/// How much smaller OpenDyslexic is set than the design size.
	static let dyslexicScale: CGFloat = 0.8

	/// The text style whose default size is closest to (and not above) `size`.
	static func textStyle(for size: CGFloat) -> Font.TextStyle {
		switch size {
			case 34...: .largeTitle
			case 28...: .title
			case 22...: .title2
			case 20...: .title3
			case 17...: .body
			case 16...: .callout
			case 15...: .subheadline
			case 13...: .footnote
			case 12...: .caption
			default: .caption2
		}
	}

	/// A system text style's default size (at the default content size).
	private static func defaultSize(of style: Font.TextStyle) -> CGFloat {
		switch style {
			case .largeTitle: 34
			case .title: 28
			case .title2: 22
			case .title3: 20
			case .headline, .body: 17
			case .callout: 16
			case .subheadline: 15
			case .footnote: 13
			case .caption: 12
			case .caption2: 11
			@unknown default: 17
		}
	}

	private static func isBold(_ weight: Font.Weight) -> Bool {
		weight == .semibold || weight == .bold || weight == .heavy || weight == .black
	}

	/// OpenDyslexic at `size` design points, shrunk and scaled with `style` under Dynamic Type.
	private static func dyslexic(_ size: CGFloat, style: Font.TextStyle, bold: Bool = false, italic: Bool = false) -> Font {
		let face = switch (bold, italic) {
			case (true, true): "OpenDyslexic-BoldItalic"
			case (true, false): "OpenDyslexic-Bold"
			case (false, true): "OpenDyslexic-Italic"
			case (false, false): "OpenDyslexic-Regular"
		}
		return .custom(face, size: size * self.dyslexicScale, relativeTo: style)
	}

	public static func serif(_ size: CGFloat) -> Font {
		if isDyslexic { return dyslexic(size, style: textStyle(for: size)) }
		return isSystemTheme ? .system(textStyle(for: size)) : .custom("InstrumentSerif-Regular", size: size, relativeTo: textStyle(for: size))
	}

	public static func serifItalic(_ size: CGFloat) -> Font {
		if isDyslexic { return dyslexic(size, style: textStyle(for: size), italic: true) }
		return isSystemTheme ? .system(textStyle(for: size)) : .custom("InstrumentSerif-Italic", size: size, relativeTo: textStyle(for: size))
	}

	public static func system(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, width: Font.Width = .standard) -> Font {
		// code and tokens stay monospaced
		if isDyslexic, design != .monospaced { return dyslexic(size, style: textStyle(for: size), bold: isBold(weight)) }
		return .system(textStyle(for: size), design: design, weight: weight).width(width)
	}

	/// A system text style (`.footnote`, `.title2`, …) for text that is set by style rather than by size: the system
	/// font, or OpenDyslexic when that is on.
	public static func text(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
		if isDyslexic { return dyslexic(defaultSize(of: style), style: style, bold: isBold(weight)) }
		return .system(style, weight: weight)
	}

	/// The font text gets when nothing sets one (form rows, plain `Text`, buttons): OpenDyslexic when it is on,
	/// otherwise `nil`, i.e. the system's own.
	static var base: Font? {
		isDyslexic ? dyslexic(defaultSize(of: .body), style: .body) : nil
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
	static let toolbar = Animation.smooth(duration: 0.35)
}

enum DTFontRegistration {
	static func registerCustomFonts() {
		let fonts: [(name: String, fileExtension: String)] = [
			("InstrumentSerif-Regular", "ttf"), ("InstrumentSerif-Italic", "ttf"),
			("OpenDyslexic-Regular", "otf"), ("OpenDyslexic-Italic", "otf"), ("OpenDyslexic-Bold", "otf"), ("OpenDyslexic-BoldItalic", "otf")
		]
		for font in fonts {
			guard let url = Bundle.main.url(forResource: font.name, withExtension: font.fileExtension) else { continue }
			CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
		}
	}
}
