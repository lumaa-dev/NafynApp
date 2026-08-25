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
		AppAppearance.configureNavigationBar()
	}

	private var context: ModelContext = {
		guard let container: ModelContainer = try? .init(for: AuthInfo.self, configurations: .init(allowsSave: true)) else { fatalError("Failed to create ModelContainer") }
		return .init(container)
	}()

	var body: some Scene {
		WindowGroup {
			RootView()
				.tint(Color.blue)
				.preferredColorScheme(ThemeManager.shared.preferredColorScheme)
		}
		.modelContext(self.context)
	}
}
