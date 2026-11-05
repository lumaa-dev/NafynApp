// Made by Lumaa

import SwiftUI

/// The equalizer's one gradient, left (bass) to right (treble): Midnight Sub-Violet, Resonant Coral / Amber,
/// Electric Cyan. The frequency curve, its fill, the spectrum, the control points and the slider glass all
/// read from here, so a color always means the same frequency region.
enum EQGradient {
	private struct Stop {
		let location: Double
		let red: Double
		let green: Double
		let blue: Double
	}

	private static let stops: [Stop] = [
		Stop(location: 0, red: 0.29, green: 0.18, blue: 0.82), // Midnight Sub-Violet
		Stop(location: 0.42, red: 1.00, green: 0.42, blue: 0.36), // Resonant Coral
		Stop(location: 0.62, red: 1.00, green: 0.71, blue: 0.24), // Amber
		Stop(location: 1, red: 0.12, green: 0.90, blue: 1.00), // Electric Cyan
	]

	static let gradient = Gradient(stops: EQGradient.stops.map { stop in
		Gradient.Stop(color: Color(red: stop.red, green: stop.green, blue: stop.blue), location: stop.location)
	})

	/// The gradient's color at a normalized position (0 = bass edge, 1 = treble edge).
	static func color(at position: Double) -> Color {
		let x = min(max(position, 0), 1)
		let upperIndex = EQGradient.stops.firstIndex { $0.location >= x } ?? EQGradient.stops.count - 1
		let upper = EQGradient.stops[upperIndex]
		let lower = EQGradient.stops[max(upperIndex - 1, 0)]
		let span = upper.location - lower.location
		let t = span > 0 ? (x - lower.location) / span : 0
		return Color(
			red: lower.red + (upper.red - lower.red) * t,
			green: lower.green + (upper.green - lower.green) * t,
			blue: lower.blue + (upper.blue - lower.blue) * t
		)
	}

	/// The gradient as a horizontal `ShapeStyle`, for views.
	static var horizontal: LinearGradient {
		LinearGradient(gradient: EQGradient.gradient, startPoint: .leading, endPoint: .trailing)
	}
}
