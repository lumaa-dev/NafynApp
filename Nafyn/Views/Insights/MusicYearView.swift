// Made by Lumaa

import SwiftUI

/// Deep-link entry point for "Your Music Year" — a thin wrapper constructing the unified
/// ``InsightsView`` with a yearly starting period. Kept as its own type (rather than folding into
/// `Navigator.Paths.musicYear(year:)` directly) so that enum's `view` doesn't need touching.
struct MusicYearView: View {
	/// The year to show, or `nil` for the current year.
	let year: Int?

	var body: some View {
		InsightsView(initialPeriod: .year(self.year ?? Calendar.current.component(.year, from: .now)))
	}
}
