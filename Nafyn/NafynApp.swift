// Made by Lumaa

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct NafynApp: App {
	init() {
		DTFontRegistration.registerCustomFonts()
		Self.configureAppearance()
	}

	private static func configureAppearance() {
		#if canImport(UIKit)
		// No background color here on purpose: every screen paints its own `DTColor.background`, and
		// scrollable content uses `.scrollEdgeEffectStyle(.soft, for: .all)` for the nav/tab-bar edge
		// material, so the nav bar itself should stay transparent rather than painting a second,
		// possibly-inconsistent background over content.
		let titleColor = UIColor(DTColor.textPrimary)
		let titleFont = UIFont(name: "InstrumentSerif-Italic", size: 20) ?? UIFont.systemFont(ofSize: 20)
		let largeTitleFont = UIFont(name: "InstrumentSerif-Italic", size: 34) ?? UIFont.systemFont(ofSize: 34)

		let navAppearance = UINavigationBarAppearance()
		navAppearance.configureWithTransparentBackground()
		navAppearance.titleTextAttributes = [.font: titleFont, .foregroundColor: titleColor]
		navAppearance.largeTitleTextAttributes = [.font: largeTitleFont, .foregroundColor: titleColor]
		UINavigationBar.appearance().standardAppearance = navAppearance
		UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
		UINavigationBar.appearance().compactAppearance = navAppearance
		UINavigationBar.appearance().tintColor = titleColor

		UITableView.appearance().backgroundColor = .clear
		UICollectionView.appearance().backgroundColor = .clear
		#endif
	}

	private var context: ModelContext = {
		guard let container: ModelContainer = try? .init(for: AuthInfo.self, configurations: .init(allowsSave: true)) else { fatalError("Failed to create ModelContainer") }
		return .init(container)
	}()

	var body: some Scene {
		WindowGroup {
			RootView()
		}
		.modelContext(self.context)
	}
}
