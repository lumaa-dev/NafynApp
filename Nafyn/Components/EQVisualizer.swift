// Made by Lumaa

import SwiftUI

/// How a gain maps to a height, shared by the visualizer and the sliders so a thumb always sits exactly on
/// the curve.
enum EQGeometry {
	/// Space kept above 0 dB's +12 and below its -12, so a thumb at either end stays inside the panel.
	static let verticalInset: CGFloat = 22

	static func y(for gain: Double, height: CGFloat) -> CGFloat {
		let range = EqualizerEngine.gainRange
		let travel = height / 2 - self.verticalInset
		return height / 2 - CGFloat(gain / range.upperBound) * travel
	}

	static func gain(forY y: CGFloat, height: CGFloat) -> Double {
		let range = EqualizerEngine.gainRange
		let travel = height / 2 - self.verticalInset
		guard travel > 0 else { return 0 }
		let gain = Double((height / 2 - y) / travel) * range.upperBound
		return min(max(gain, range.lowerBound), range.upperBound)
	}

	/// Center of band `index` along a width split into one column per band.
	static func x(forBand index: Int, width: CGFloat) -> CGFloat {
		(CGFloat(index) + 0.5) / CGFloat(EQScale.bandCount) * width
	}
}

/// Smooths the analyzer's raw spectrum for display: levels jump up fast and fall slowly, and go quiet when
/// the audio stops. A class on purpose: it is advanced by the `TimelineView` every frame without invalidating
/// any view.
private final class SpectrumDisplay {
	private(set) var levels = [Float](repeating: 0, count: EQScale.spectrumPointCount)
	private var lastFrame: Date?

	func advance(to now: Date) -> [Float] {
		let elapsed = self.lastFrame.map { min(now.timeIntervalSince($0), 0.1) } ?? 1.0 / 60
		self.lastFrame = now

		let latest = SpectrumStore.shared.read()
		// Playback paused or stopped: the audio thread stops publishing, so ignore what's left
		let isFresh = CFAbsoluteTimeGetCurrent() - latest.stamp < 0.15

		// per-frame factors, expressed per 1/60 s so the feel doesn't depend on the refresh rate
		let rise = Float(1 - pow(1 - 0.55, elapsed * 60))
		let fall = Float(1 - pow(1 - 0.10, elapsed * 60))

		for index in self.levels.indices {
			let target = isFresh ? latest.levels[index] : 0
			let factor = target > self.levels[index] ? rise : fall
			self.levels[index] += (target - self.levels[index]) * factor
		}
		return self.levels
	}
}

/// The equalizer's picture, in a single `Canvas`: a live spectrum behind the frequency-response curve that
/// passes through every band's gain, both painted with ``EQGradient`` from bass (left) to treble (right).
///
/// It draws into whatever size it is given, one column per band; lay the band sliders over it with the same
/// width and they line up with the curve's control points.
struct EQVisualizer: View {
	let gains: [Double]
	/// Audio is playing through the equalizer: the spectrum animates. Otherwise it settles and the frame
	/// clock stops.
	let isLive: Bool

	@State private var display = SpectrumDisplay()
	@State private var isPaused: Bool

	init(gains: [Double], isLive: Bool) {
		self.gains = gains
		self.isLive = isLive
		self._isPaused = State(initialValue: !isLive)
	}

	var body: some View {
		TimelineView(.animation(minimumInterval: 1.0 / 60, paused: self.isPaused)) { timeline in
			let spectrum = self.display.advance(to: timeline.date)
			Canvas { context, size in
				EQVisualizer.draw(gains: self.gains, spectrum: spectrum, in: &context, size: size)
			}
		}
		.task(id: self.isLive) {
			if self.isLive {
				self.isPaused = false
			} else {
				// let the spectrum fall to silence before the frame clock stops
				try? await Task.sleep(for: .seconds(1))
				self.isPaused = true
			}
		}
		.accessibilityHidden(true)
	}

	// MARK: - Drawing

	private static func draw(gains: [Double], spectrum: [Float], in context: inout GraphicsContext, size: CGSize) {
		guard size.width > 0, size.height > 0 else { return }

		let gradient = EQGradient.gradient
		let horizontal = GraphicsContext.Shading.linearGradient(
			gradient,
			startPoint: CGPoint(x: 0, y: 0),
			endPoint: CGPoint(x: size.width, y: 0)
		)

		self.drawZeroLine(in: &context, size: size)
		self.drawSpectrum(spectrum, shading: horizontal, in: &context, size: size)
		self.drawCurve(gains: gains, shading: horizontal, in: &context, size: size)
	}

	/// The subtle 0 dB reference line.
	private static func drawZeroLine(in context: inout GraphicsContext, size: CGSize) {
		var line = Path()
		let y = EQGeometry.y(for: 0, height: size.height)
		line.move(to: CGPoint(x: 0, y: y))
		line.addLine(to: CGPoint(x: size.width, y: y))
		context.stroke(line, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
	}

	/// A filled waveform that fades toward the bottom.
	private static func drawSpectrum(_ spectrum: [Float], shading: GraphicsContext.Shading, in context: inout GraphicsContext, size: CGSize) {
		guard spectrum.contains(where: { $0 > 0.004 }) else { return }

		// neighbors blended so single bins don't spike
		let smoothed = spectrum.indices.map { index -> CGFloat in
			let previous = spectrum[max(index - 1, 0)]
			let next = spectrum[min(index + 1, spectrum.count - 1)]
			return CGFloat(previous * 0.25 + spectrum[index] * 0.5 + next * 0.25)
		}

		let maximumHeight = size.height * 0.9
		let points = smoothed.enumerated().map { index, level in
			CGPoint(
				x: (CGFloat(index) + 0.5) / CGFloat(smoothed.count) * size.width,
				y: size.height - level * maximumHeight
			)
		}

		var outline = Path()
		outline.move(to: CGPoint(x: 0, y: points[0].y))
		outline.addLine(to: points[0])
		for index in 1..<points.count {
			let midpoint = CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
			outline.addQuadCurve(to: midpoint, control: points[index - 1])
		}
		outline.addLine(to: points[points.count - 1])
		outline.addLine(to: CGPoint(x: size.width, y: points[points.count - 1].y))

		var area = outline
		area.addLine(to: CGPoint(x: size.width, y: size.height))
		area.addLine(to: CGPoint(x: 0, y: size.height))
		area.closeSubpath()

		context.drawLayer { layer in
			layer.fill(area, with: shading)
			// keep the gradient where the fill is, fade it out toward the bottom
			layer.blendMode = .destinationIn
			layer.fill(
				Path(CGRect(origin: .zero, size: size)),
				with: .linearGradient(
					Gradient(colors: [.white.opacity(0.55), .white.opacity(0.06)]),
					startPoint: .zero,
					endPoint: CGPoint(x: 0, y: size.height)
				)
			)
		}

		context.stroke(outline, with: shading, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
	}

	/// The Catmull-Rom curve through every band, its soft fill and the control points.
	private static func drawCurve(gains: [Double], shading: GraphicsContext.Shading, in context: inout GraphicsContext, size: CGSize) {
		guard gains.count == EQScale.bandCount else { return }

		let bandPoints = gains.enumerated().map { index, gain in
			CGPoint(x: EQGeometry.x(forBand: index, width: size.width), y: EQGeometry.y(for: gain, height: size.height))
		}
		// flat tails out to both edges so the curve spans the full width
		let points = [CGPoint(x: 0, y: bandPoints[0].y)] + bandPoints + [CGPoint(x: size.width, y: bandPoints[bandPoints.count - 1].y)]

		var curve = Path()
		curve.move(to: points[0])
		for index in 0..<(points.count - 1) {
			let p0 = points[max(index - 1, 0)]
			let p1 = points[index]
			let p2 = points[index + 1]
			let p3 = points[min(index + 2, points.count - 1)]
			curve.addCurve(
				to: p2,
				control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
				control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
			)
		}

		var area = curve
		area.addLine(to: CGPoint(x: size.width, y: size.height))
		area.addLine(to: CGPoint(x: 0, y: size.height))
		area.closeSubpath()

		context.drawLayer { layer in
			layer.fill(area, with: shading)
			layer.blendMode = .destinationIn
			layer.fill(
				Path(CGRect(origin: .zero, size: size)),
				with: .linearGradient(
					Gradient(colors: [.white.opacity(0.30), .white.opacity(0)]),
					startPoint: .zero,
					endPoint: CGPoint(x: 0, y: size.height)
				)
			)
		}

		context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

		for point in bandPoints {
			let radius: CGFloat = 4
			let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
			context.fill(dot, with: .color(.white))
			context.stroke(dot, with: .color(EQGradient.color(at: Double(point.x / size.width))), lineWidth: 2)
		}
	}
}
