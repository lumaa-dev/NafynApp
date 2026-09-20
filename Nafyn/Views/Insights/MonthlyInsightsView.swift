// Made by Lumaa

import SwiftUI

/// Deep-link entry point for the monthly summary — a thin wrapper constructing the unified
/// ``InsightsView`` with a monthly starting period. Kept as its own type (rather than folding into
/// `Navigator.Paths.monthlyInsights(month:)` directly) so that enum's `view` doesn't need touching.
struct MonthlyInsightsView: View {
	/// The `YYYY-MM` month to show, or `nil` for the month in progress.
	let month: String?

	var body: some View {
		InsightsView(initialPeriod: .month(self.month ?? InsightsFormat.monthIdentifier(.now)))
	}
}
