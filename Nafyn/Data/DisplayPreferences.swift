// Made by Lumaa

import Foundation
import Safyn

/// App-wide mirror of the server's `AppearanceSettings` (`User.appearanceSettings`), cached locally so
/// track lists can read it synchronously (`TrackRow`) without an async fetch on every screen. Seeded from
/// `UserDefaults` at launch, then refreshed from the server and kept in sync by `SettingsView`'s
/// appearance section whenever the user changes it there.
@Observable
final class DisplayPreferences {
	static let shared = DisplayPreferences()

	private static let showFileSizeKey = "settings.showFileSize"
	private static let showDurationKey = "settings.showDuration"

	var showFileSize: Bool {
		didSet {
			guard oldValue != self.showFileSize else { return }
			UserDefaults.standard.set(self.showFileSize, forKey: Self.showFileSizeKey)
		}
	}

	var showDuration: Bool {
		didSet {
			guard oldValue != self.showDuration else { return }
			UserDefaults.standard.set(self.showDuration, forKey: Self.showDurationKey)
		}
	}

	private init() {
		let defaults = UserDefaults.standard
		self.showFileSize = defaults.object(forKey: Self.showFileSizeKey) as? Bool ?? false
		// Duration has always been shown in every `TrackRow` prior to this setting existing, so a
		// user who's never touched it (or never opened Settings since updating) keeps seeing it.
		self.showDuration = defaults.object(forKey: Self.showDurationKey) as? Bool ?? true
	}

	func apply(_ settings: AppearanceSettings) {
		self.showFileSize = settings.showFileSize
		self.showDuration = settings.showDuration
	}
}
