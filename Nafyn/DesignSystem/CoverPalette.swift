// Made by Lumaa

import SwiftUI

/// The colors of a detail screen themed after its cover: a uni-color background derived from the cover's
/// dominant color, and the text colors that stay legible on it.
///
/// In dark appearance (the default theme always, the system theme when the device is dark) the cover color
/// is mixed with black until white text reaches WCAG AAA contrast (7:1); in light appearance it is mixed with white
/// and the text is black. Without cover colors (offline, no cover) it falls back to the design-system
/// background.
struct CoverPalette: Equatable {
	/// The uni-color behind the whole screen.
	let background: Color
	/// Tappable text and icons.
	let primary: Color
	/// Non-tappable text and icons.
	let secondary: Color

	init(imageColors: [String]?, colorScheme: ColorScheme) {
		let isDark = colorScheme == .dark
		// Mixed toward a near-black / near-white rather than pure black / white, and clamped afterwards: a
		// black or white cover (or an extreme mix) must never give a #000000 or #FFFFFF screen.
		let target: RGB = isDark ? RGB(r: 0.1, g: 0.1, b: 0.1) : RGB(r: 0.94, g: 0.94, b: 0.94)
		let limits: ClosedRange<Double> = isDark ? 0.07...0.93 : 0.07...0.95

		let background: RGB
		if let hex = imageColors?.first, let base = RGB(hex: hex) {
			// Never a flat tint of the raw cover color: always pulled toward black (dark) or white (light)
			// so text contrast holds whatever the cover looks like.
			var amount = isDark ? 0.55 : 0.7
			var mixed = base.mixed(with: target, amount: amount).clamped(to: limits)
			while amount < 0.95, mixed.contrast(with: isDark ? .white : .black) < 7.1 {
				amount += 0.05
				mixed = base.mixed(with: target, amount: amount).clamped(to: limits)
			}
			background = mixed
		} else {
			background = isDark ? RGB(hex: "2A2A27")! : RGB(hex: "F2F2F7")!
		}

		let text: Color = isDark ? .white : .black
		self.background = background.color
		self.primary = text
		// DESIGN.md "Contrast" (WCAG AAA): a dimmed label cannot keep 7:1, so the secondary one is the full label color
		self.secondary = text
	}

	private struct RGB {
		var r: Double
		var g: Double
		var b: Double

		static let black = RGB(r: 0, g: 0, b: 0)
		static let white = RGB(r: 1, g: 1, b: 1)

		init(r: Double, g: Double, b: Double) {
			self.r = r
			self.g = g
			self.b = b
		}

		init?(hex: String) {
			let digits = hex.trimmingCharacters(in: .alphanumerics.inverted)
			guard digits.count == 6, let value = UInt64(digits, radix: 16) else { return nil }
			self.init(
				r: Double((value >> 16) & 0xFF) / 255,
				g: Double((value >> 8) & 0xFF) / 255,
				b: Double(value & 0xFF) / 255
			)
		}

		var color: Color { Color(red: self.r, green: self.g, blue: self.b) }

		func mixed(with other: RGB, amount: Double) -> RGB {
			RGB(
				r: self.r + (other.r - self.r) * amount,
				g: self.g + (other.g - self.g) * amount,
				b: self.b + (other.b - self.b) * amount
			)
		}

		func clamped(to range: ClosedRange<Double>) -> RGB {
			RGB(
				r: min(max(self.r, range.lowerBound), range.upperBound),
				g: min(max(self.g, range.lowerBound), range.upperBound),
				b: min(max(self.b, range.lowerBound), range.upperBound)
			)
		}

		/// WCAG relative luminance.
		private var luminance: Double {
			func linear(_ value: Double) -> Double {
				value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
			}
			return 0.2126 * linear(self.r) + 0.7152 * linear(self.g) + 0.0722 * linear(self.b)
		}

		/// WCAG contrast ratio, 1...21.
		func contrast(with other: RGB) -> Double {
			let a = self.luminance
			let b = other.luminance
			return (max(a, b) + 0.05) / (min(a, b) + 0.05)
		}
	}
}

private struct CoverPaletteKey: EnvironmentKey {
	static let defaultValue: CoverPalette? = nil
}

extension EnvironmentValues {
	/// Set by cover-themed detail screens so shared rows (`TrackRow`) pick the palette's text colors.
	var coverPalette: CoverPalette? {
		get { self[CoverPaletteKey.self] }
		set { self[CoverPaletteKey.self] = newValue }
	}
}
