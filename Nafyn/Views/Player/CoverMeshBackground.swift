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
				colors: [Color.black.opacity(0.32), Color.black.opacity(0.52)],
				startPoint: .top,
				endPoint: .bottom
			)
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
