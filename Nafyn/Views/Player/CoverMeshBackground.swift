// Made by Lumaa

import SwiftUI

/// Animated mesh-gradient background for `NowPlayingView`, colored from the current track's cover art
/// (via `CoverPaletteExtractor`) and subtly modulated by `AudioReactivityEngine`'s bass/overall levels.
/// Motion is driven entirely by `TimelineView(.animation)` plus a handful of cheap trig calls per frame —
/// no layout or image work happens per-frame — so it stays smooth on any supported device.
struct CoverMeshBackground: View {
	let coverURL: URL?

	@State private var palette: [Color] = CoverPaletteExtractor.fallback

	private static let gridSize = 4

	/// DESIGN.md "Contrast" (WCAG AAA): white labels need 7:1, i.e. a background luminance of at most ~0.1. The scrim
	/// is as dark as the brightest color of the palette requires (never lighter than before), so a bright cover
	/// is darkened until its labels read - the gradient itself keeps its hue and motion.
	private var scrimOpacity: Double {
		let brightest = self.palette.map { Self.luminance(of: $0) }.max() ?? 0
		guard brightest > 0.1 else { return 0.52 }
		return min(0.9, max(0.52, 1 - pow(0.1 / brightest, 1 / 2.2)))
	}

	private static func luminance(of color: Color) -> Double {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
		func linear(_ c: CGFloat) -> Double {
			let v = Double(c)
			return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
	}

	var body: some View {
		TimelineView(.animation) { context in
			let time = context.date.timeIntervalSinceReferenceDate
			let bass = AudioReactivityEngine.shared.bassLevel
			let overall = AudioReactivityEngine.shared.overallLevel

			MeshGradient(
				width: Self.gridSize,
				height: Self.gridSize,
				points: self.points(time: time, bass: bass, overall: overall),
				colors: self.colors()
			)
		}
		.overlay {
			// Guarantees label legibility over any cover palette — the mesh must never compromise
			// readability — without flattening the gradient's motion into invisibility.
			LinearGradient(
				colors: [Color.black.opacity(self.scrimOpacity * 0.85), Color.black.opacity(self.scrimOpacity)],
				startPoint: .top,
				endPoint: .bottom
			)
			.animation(.easeInOut(duration: 0.6), value: self.scrimOpacity)
		}
		.task(id: self.coverURL) {
			let newPalette = await CoverPaletteExtractor.palette(for: self.coverURL)
			withAnimation(.easeInOut(duration: 0.6)) {
				self.palette = newPalette
			}
		}
	}

	/// A 4x4 grid of unit-space control points. Every point on the outer border (not just the 4 corners)
	/// stays pinned so the mesh always fully covers the view with no seams at the edges; only the interior
	/// points drift, each on its own slow, uniquely-phased sine wave, with amplitude that grows slightly
	/// with `overall`/`bass` so audible energy nudges the motion without ever snapping it.
	private func points(time: Double, bass: Double, overall: Double) -> [SIMD2<Float>] {
		let size = Self.gridSize
		var result: [SIMD2<Float>] = []
		result.reserveCapacity(size * size)

		let baseAmplitude = 0.05
		let reactiveAmplitude = 0.05 * (0.4 + 0.6 * overall)
		let bassBoost = 0.03 * bass

		for row in 0..<size {
			for col in 0..<size {
				let baseX = Float(col) / Float(size - 1)
				let baseY = Float(row) / Float(size - 1)

				let isBorder = row == 0 || row == size - 1 || col == 0 || col == size - 1
				if isBorder {
					result.append(SIMD2<Float>(baseX, baseY))
					continue
				}

				let phase = Double(row * size + col) * 0.9
				let driftX = sin(time * 0.15 + phase) * (baseAmplitude + reactiveAmplitude)
				let driftY = cos(time * 0.12 + phase * 1.3) * (baseAmplitude + reactiveAmplitude + bassBoost)

				result.append(SIMD2<Float>(baseX + Float(driftX), baseY + Float(driftY)))
			}
		}
		return result
	}

	/// Maps the (3-4 color) extracted palette across all 16 mesh points, cycling through it so adjacent
	/// points aren't all identical — reads as a richer gradient than a flat tile of 3 colors.
	private func colors() -> [Color] {
		(0..<(Self.gridSize * Self.gridSize)).map { self.palette[$0 % self.palette.count] }
	}
}
