// Made by Lumaa

import SwiftUI
import UnionToast

/// A single toast message, shown via ``ToastState`` and the `.toast(_:)` view modifier below.
struct ToastMessage: Identifiable, Equatable {
	let id: UUID = UUID()
	let text: String
	let symbol: String
}

/// Per-screen toast state, following the same error-toast pattern already used by `OnboardingView`
/// (backed by the `UnionToast` package), extended with a success variant for the many new mutating
/// actions (Request, Add to Playlist, Delete, Reorder, ...) that need brief feedback.
@Observable
final class ToastState {
	var current: ToastMessage? = nil

	func success(_ text: String) {
		self.current = ToastMessage(text: text, symbol: "checkmark.seal")
		Task { @MainActor in Haptics.success() }
	}

	func failure(_ error: Error) {
		self.current = ToastMessage(text: error.localizedDescription, symbol: "xmark.seal")
		Task { @MainActor in Haptics.error() }
	}
}

extension View {
	func toast(_ state: ToastState) -> some View {
		self.toast(item: Binding(get: { state.current }, set: { state.current = $0 })) { message in
			Label(message.text, systemImage: message.symbol)
				.foregroundStyle(DTColor.textPrimary)
		}
	}
}
