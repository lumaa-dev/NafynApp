// Made by Lumaa

import SwiftUI
import Safyn

/// Shared formatting for the Insights screens: durations, period identifiers, and month labels.
///
/// Every Insights period is a plain string in the API's own format (`YYYY-MM` months, `YYYY-Www` ISO
/// weeks), so parsing/printing them lives here rather than being re-derived per screen.
enum InsightsFormat {
	/// Minutes as a compact "12h 34m" (or "34m" under an hour), for the headline totals.
	static func minutes(_ total: Int) -> String {
		let hours = total / 60
		let minutes = total % 60
		if hours <= 0 {
			return String(localized: "\(minutes)-minutes-short")
		}
		return String(localized: "\(hours)-hours-\(minutes)-minutes-short")
	}

	/// A count with thousands separators.
	static func count(_ value: Int) -> String {
		value.formatted(.number.grouping(.automatic))
	}

	/// A signed percentage change between two totals, or `nil` when the previous total was zero.
	static func percentChange(from previous: Int, to current: Int) -> Int? {
		guard previous > 0 else { return nil }
		return Int((Double(current - previous) / Double(previous) * 100).rounded())
	}

	/// The localized full month name for a 1-based month number.
	static func monthName(_ month: Int) -> String {
		let symbols = Calendar.current.standaloneMonthSymbols
		guard symbols.indices.contains(month - 1) else { return String(month) }
		return symbols[month - 1]
	}

	/// The localized single-letter month initial for a 1-based month number, for dense axis labels.
	static func monthInitial(_ month: Int) -> String {
		String(self.monthName(month).prefix(1))
	}

	/// A `YYYY-MM` identifier for a date.
	static func monthIdentifier(_ date: Date) -> String {
		let components = Calendar.current.dateComponents([.year, .month], from: date)
		return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 1)
	}

	/// A `YYYY-MM` identifier printed as "March 2026".
	static func monthLabel(_ identifier: String) -> String {
		let parts = identifier.split(separator: "-")
		guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return identifier }
		return String(localized: "\(self.monthName(month))-\(String(year))-month-year")
	}

	/// The `YYYY-MM` identifier `offset` months away from `identifier`.
	static func month(_ identifier: String, offsetBy offset: Int) -> String {
		let parts = identifier.split(separator: "-")
		guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return identifier }

		var components = DateComponents()
		components.year = year
		components.month = month
		components.day = 1

		guard
			let date = Calendar.current.date(from: components),
			let shifted = Calendar.current.date(byAdding: .month, value: offset, to: date)
		else { return identifier }

		return self.monthIdentifier(shifted)
	}

	/// A `YYYY-MM-DD` day identifier printed as a short day-of-month label.
	static func dayLabel(_ identifier: String) -> String {
		guard let day = identifier.split(separator: "-").last, let value = Int(day) else { return identifier }
		return String(value)
	}

	/// An hour of day (`0...23`) printed in the user's locale, e.g. "14" or "2 PM".
	static func hourLabel(_ hour: Int) -> String {
		var components = DateComponents()
		components.hour = hour
		components.minute = 0
		guard let date = Calendar.current.date(from: components) else { return String(hour) }
		return date.formatted(.dateTime.hour())
	}

	/// A Unix millisecond timestamp as a relative "2 days ago" string.
	static func relative(millis: Int64) -> String {
		let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
		return date.formatted(.relative(presentation: .named))
	}
}
