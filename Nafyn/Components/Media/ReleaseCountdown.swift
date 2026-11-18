// Made by Lumaa

import SwiftUI

/// Pure time math behind ``ReleaseCountdown``, kept free of SwiftUI so it can be exercised on its own.
///
/// Ports `ReleaseCountdown.vue`: months are calendar months, the rest are fixed-length units (7 days = 1 week).
enum ReleaseCountdownMath {
	enum Unit: CaseIterable {
		case months, weeks, days, hours, minutes, seconds
	}

	struct Part: Equatable {
		let unit: Unit
		let value: Int
	}

	/// Local midnight of the release *day*. The API sends the day as UTC midnight, so the calendar date is
	/// read in UTC and rebuilt in `calendar`'s zone — the same instant the server notifies subscribers at.
	static func target(for releaseDate: Date, calendar: Calendar = .current) -> Date {
		var utc = Calendar(identifier: .gregorian)
		utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
		let day = utc.dateComponents([.year, .month, .day], from: releaseDate)
		return calendar.date(from: day) ?? releaseDate
	}

	/// The remaining time split into units, with leading zero units dropped and inner ones kept
	/// (`1 month, 0 weeks, 2 days`). Empty once `now` has reached `end`.
	///
	/// Always computed from `now`, never decremented, so a clock or timezone change can't desync it.
	static func parts(from now: Date, to end: Date, calendar: Calendar = .current) -> [Part] {
		guard now < end else { return [] }

		// calendar months first, then fixed-length units for whatever is left
		var months = 0
		while months < 12 * 200, let next = calendar.date(byAdding: .month, value: months + 1, to: now), next <= end {
			months += 1
		}
		let anchor = calendar.date(byAdding: .month, value: months, to: now) ?? now
		var rest = Int(end.timeIntervalSince(anchor).rounded(.down))

		let weeks = rest / 604_800
		rest -= weeks * 604_800
		let days = rest / 86_400
		rest -= days * 86_400
		let hours = rest / 3600
		rest -= hours * 3600
		let minutes = rest / 60
		let seconds = rest - minutes * 60

		let all = [
			Part(unit: .months, value: months),
			Part(unit: .weeks, value: weeks),
			Part(unit: .days, value: days),
			Part(unit: .hours, value: hours),
			Part(unit: .minutes, value: minutes),
			Part(unit: .seconds, value: seconds),
		]
		guard let first = all.firstIndex(where: { $0.value > 0 }) else { return [] }
		return Array(all[first...])
	}

	static func longText(_ parts: [Part]) -> String {
		parts.map { Self.long($0) }.joined(separator: ", ")
	}

	static func compactText(_ parts: [Part]) -> String {
		parts.map { Self.short($0) }.joined(separator: " ")
	}

	private static func long(_ part: Part) -> String {
		switch part.unit {
			case .months: String(localized: "countdown-months \(part.value)")
			case .weeks: String(localized: "countdown-weeks \(part.value)")
			case .days: String(localized: "countdown-days \(part.value)")
			case .hours: String(localized: "countdown-hours \(part.value)")
			case .minutes: String(localized: "countdown-minutes \(part.value)")
			case .seconds: String(localized: "countdown-seconds \(part.value)")
		}
	}

	private static func short(_ part: Part) -> String {
		switch part.unit {
			case .months: String(localized: "countdown-short-months \(part.value)")
			case .weeks: String(localized: "countdown-short-weeks \(part.value)")
			case .days: String(localized: "countdown-short-days \(part.value)")
			case .hours: String(localized: "countdown-short-hours \(part.value)")
			case .minutes: String(localized: "countdown-short-minutes \(part.value)")
			case .seconds: String(localized: "countdown-short-seconds \(part.value)")
		}
	}
}

/// Ticking countdown to local midnight on a release day; port of the web app's `ReleaseCountdown.vue`.
///
/// `releaseDate` is the API's UTC-midnight date. Reads "Out now" once the moment has passed and calls
/// `onReleased` on the tick that crosses it, so the screen can reload (and offer Request instead).
struct ReleaseCountdown: View {
	var releaseDate: Date
	var compact: Bool = false
	var onReleased: (() -> Void)? = nil

	private var target: Date {
		ReleaseCountdownMath.target(for: self.releaseDate)
	}

	/// Spoken instead of the ticking text: the full date, so VoiceOver isn't re-announcing every second.
	private var spokenLabel: String {
		self.target.formatted(date: .complete, time: .shortened)
	}

	var body: some View {
		// `TimelineView` stops ticking while off-screen and recomputes from the wall clock every time
		TimelineView(.periodic(from: .now, by: 1)) { context in
			CountdownText(parts: ReleaseCountdownMath.parts(from: context.date, to: self.target), compact: self.compact, onReleased: self.onReleased)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(self.spokenLabel)
	}
}

private struct CountdownText: View {
	let parts: [ReleaseCountdownMath.Part]
	let compact: Bool
	let onReleased: (() -> Void)?

	@Environment(\.coverPalette) private var palette

	var body: some View {
		Group {
			if self.parts.isEmpty {
				Text("out-now")
			} else if self.compact {
				Text(ReleaseCountdownMath.compactText(self.parts))
					.font(DTFont.system(12).monospacedDigit())
					.foregroundStyle(self.palette?.primary ?? DTColor.textPrimary.opacity(0.5))
					.lineLimit(1)
			} else {
				Text(ReleaseCountdownMath.longText(self.parts))
					.monospacedDigit()
			}
		}
		// only a real tick across zero fires this, not a view that appears already past the date — otherwise
		// a server that still says "unreleased" would reload this screen in a loop
		.onChange(of: self.parts.isEmpty) { _, isOut in
			if isOut { self.onReleased?() }
		}
	}
}
