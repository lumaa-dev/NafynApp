// Made by Lumaa

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Only here for the two things SwiftUI has no equivalent of: the APNs token callbacks, and installing the
/// notification delegate before launch finishes (a tap that cold-starts the app is delivered to it).
final class AppDelegate: NSObject, UIApplicationDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
		PushManager.shared.installDelegate()
		return true
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		PushManager.shared.didRegister(deviceToken: deviceToken)
	}

	// no logging of the failure's details: nothing here is worth the risk of echoing a token
	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

@main
struct NafynApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	/// Shared `ModelContainer` for every SwiftData model in the app — ``AuthInfo`` and
	/// ``DownloadedTrack``. Exposed at the type level (not just as this struct's `context` below) so
	/// ``DownloadManager``, a plain singleton with no SwiftUI environment of its own, can open its own
	/// `ModelContext` against the same store.
	static let container: ModelContainer = {
		guard let container: ModelContainer = try? .init(for: AuthInfo.self, DownloadedTrack.self, configurations: .init(allowsSave: true)) else { fatalError("Failed to create ModelContainer") }
		return container
	}()

	init() {
		DTFontRegistration.registerCustomFonts()
		AppAppearance.configureNavigationBar()

		// `BGTaskScheduler.shared.register(forTaskWithIdentifier:...)` must happen before the app
		// finishes launching, or every later `submit(_:)` for that identifier throws — touching the
		// singleton here (its `init` registers the handler) is early enough.
		_ = DownloadManager.shared
	}

	private var context: ModelContext = ModelContext(NafynApp.container)

	var body: some Scene {
		WindowGroup {
			RootView()
				.tint(Color.blue)
				.preferredColorScheme(ThemeManager.shared.preferredColorScheme)
		}
		.modelContext(self.context)
	}
}
