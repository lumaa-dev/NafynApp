// Made by Lumaa

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTheme: String, CaseIterable, Identifiable {
	case `default`
	case system

	var id: String { self.rawValue }

	var label: String {
		switch self {
			case .default: String(localized: "theme-default")
			case .system: String(localized: "theme-system")
		}
	}

	var symbolName: String {
		switch self {
			case .default: "moon.stars.fill"
			case .system: "circle.lefthalf.filled"
		}
	}
}

/// App-wide theme switch: `.default` keeps Nafyn's custom all-dark styling (Instrument Serif, hand-picked
/// hex palette); `.system` follows Apple HIG (adaptive light/dark, SF fonts, semantic system colors).
/// `DTColor`/`DTFont` read `ThemeManager.shared.current` on every access, so switching here reactively
/// re-themes every view that already goes through those tokens — no per-view changes needed.
@Observable
final class ThemeManager {
	static let shared: ThemeManager = .init()

	private static let storageKey = "app.theme"

	var current: AppTheme {
		didSet {
			guard oldValue != self.current else { return }
			UserDefaults.standard.set(self.current.rawValue, forKey: Self.storageKey)
			AppAppearance.configureNavigationBar()
		}
	}

	var preferredColorScheme: ColorScheme? {
		switch self.current {
			case .default: .dark
			case .system: nil
		}
	}

	private init() {
		if let raw = UserDefaults.standard.string(forKey: Self.storageKey), let theme = AppTheme(rawValue: raw) {
			self.current = theme
		} else {
			self.current = .default
		}
	}
}

enum AppAppearance {
	static func configureNavigationBar() {
		#if canImport(UIKit)
		let navAppearance = UINavigationBarAppearance()

		switch ThemeManager.shared.current {
			case .default:
				// No opaque background here on purpose: every screen paints its own `DTColor.background`,
				// so the nav bar itself stays transparent rather than painting a second, possibly-
				// inconsistent background over content.
				navAppearance.configureWithTransparentBackground()
				let titleColor = UIColor(DTColor.textPrimary)
				// scaled through UIFontMetrics so the bar titles follow Dynamic Type too
				let titleFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont(name: "InstrumentSerif-Italic", size: 20) ?? UIFont.systemFont(ofSize: 20))
				let largeTitleFont = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(name: "InstrumentSerif-Italic", size: 34) ?? UIFont.systemFont(ofSize: 34))
				navAppearance.titleTextAttributes = [.font: titleFont, .foregroundColor: titleColor]
				navAppearance.largeTitleTextAttributes = [.font: largeTitleFont, .foregroundColor: titleColor]
				UINavigationBar.appearance().tintColor = .white
			case .system:
				navAppearance.configureWithDefaultBackground()
				UINavigationBar.appearance().tintColor = nil
		}

		if FontPreferences.shared.useDyslexic {
			// OpenDyslexic for the bar titles, whichever theme (scaled through UIFontMetrics like the serif ones)
			let titleFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont(name: "OpenDyslexic-Bold", size: 17 * DTFont.dyslexicScale) ?? UIFont.boldSystemFont(ofSize: 17))
			let largeTitleFont = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(name: "OpenDyslexic-Bold", size: 34 * DTFont.dyslexicScale) ?? UIFont.boldSystemFont(ofSize: 34))
			navAppearance.titleTextAttributes[.font] = titleFont
			navAppearance.largeTitleTextAttributes[.font] = largeTitleFont
			UITabBarItem.appearance().setTitleTextAttributes([.font: UIFontMetrics(forTextStyle: .caption2).scaledFont(for: UIFont(name: "OpenDyslexic-Regular", size: 10 * DTFont.dyslexicScale) ?? UIFont.systemFont(ofSize: 10))], for: .normal)
		} else {
			UITabBarItem.appearance().setTitleTextAttributes(nil, for: .normal)
		}

		UINavigationBar.appearance().standardAppearance = navAppearance
		UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
		UINavigationBar.appearance().compactAppearance = navAppearance

		UITableView.appearance().backgroundColor = .clear
		UICollectionView.appearance().backgroundColor = .clear
		#endif
	}
}
