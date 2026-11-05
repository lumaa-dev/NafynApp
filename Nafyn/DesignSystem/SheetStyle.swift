// Made by Lumaa

import SwiftUI

/// Makes a sheet look like the rest of the app in the default theme.
///
/// A sheet sits one elevation level above its presenter, so the system draws its backgrounds (and the rows of
/// a grouped `Form`/`List`) a step lighter than the same views pushed on a tab. Painting the sheet with the
/// app's own background and giving grouped rows the base-level row color makes both identical. The system
/// theme keeps the platform look untouched.
extension DTColor {
	/// A grouped row (`Form`/`List` section) at the base elevation level; `nil` leaves the system color.
	static var groupedRow: Color? {
		ThemeManager.shared.current == .default ? Color(hex: "1C1C1E") : nil
	}
}

private struct SheetBackgroundModifier: ViewModifier {
	@ViewBuilder
	func body(content: Content) -> some View {
		if ThemeManager.shared.current == .default {
			content
				.scrollContentBackground(.hidden)
				.presentationBackground(DTColor.background)
				// a zoom transition inside a sheet glitches (an iOS bug): no card in a sheet is a zoom source
				.environment(\.zoomNamespace, nil)
		} else {
			content
				.environment(\.zoomNamespace, nil)
		}
	}
}

extension View {
	/// Apply to the root of a sheet (its `NavigationStack`): the sheet itself, and every `List`/`Form`/`ScrollView`
	/// background inside it, is the app background instead of the system's lighter sheet gray. Also turns off card
	/// zoom transitions inside the sheet.
	func sheetBackground() -> some View {
		self.modifier(SheetBackgroundModifier())
	}

	/// Apply to each `Section` of a grouped `Form`/`List` inside a sheet, so its rows match the rows of the
	/// same form outside a sheet.
	func sheetRows() -> some View {
		self.listRowBackground(DTColor.groupedRow)
	}
}
