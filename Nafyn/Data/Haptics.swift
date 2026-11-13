// Made by Lumaa

import UIKit

/// App-wide haptic feedback for the moments SwiftUI's `.sensoryFeedback` can't reach (actions that finish later, in a
/// `Task`): a toast's success or failure, transport controls, a hold that opens something. Screens with their own
/// state trigger use `.sensoryFeedback` directly. Respects the system setting: UIKit's generators do nothing when
/// "System Haptics" is off.
@MainActor
enum Haptics {
	private static let light = UIImpactFeedbackGenerator(style: .light)
	private static let medium = UIImpactFeedbackGenerator(style: .medium)
	private static let notification = UINotificationFeedbackGenerator()
	private static let selectionGenerator = UISelectionFeedbackGenerator()

	/// Something finished well (a request sent, tracks added, a setting saved).
	static func success() {
		self.notification.notificationOccurred(.success)
	}

	/// Something failed.
	static func error() {
		self.notification.notificationOccurred(.error)
	}

	/// A transport control (play / pause, next, previous).
	static func tap() {
		self.light.impactOccurred()
	}

	/// A hold that opened something (a sheet, a menu of one's own).
	static func hold() {
		self.medium.impactOccurred()
	}

	/// A pick among several (a filter, a playlist in a picker).
	static func selection() {
		self.selectionGenerator.selectionChanged()
	}
}
