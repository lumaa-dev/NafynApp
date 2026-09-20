// Made by Lumaa

import SwiftUI
import ImageIO
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Extracts a small set of dominant colors from a cover art URL, for `CoverMeshBackground`'s animated
/// mesh gradient. Decodes at a tiny thumbnail size via `ImageIO` (never the full-resolution image) and
/// does all of its work off the main actor — this is bytes-on-the-wire plus a handful of pixel reads,
/// not something that should ever compete with UI work.
enum CoverPaletteExtractor {
	/// In-memory cache keyed by URL, since the same cover is re-requested every time `NowPlayingView`
	/// reappears for a track already seen this session.
	private static let cache = NSCache<NSString, PaletteBox>()

	private final class PaletteBox {
		let colors: [Color]
		init(_ colors: [Color]) { self.colors = colors }
	}

	/// A calm neutral fallback shown while the real palette loads, or if extraction fails.
	static let fallback: [Color] = [
		Color(hex: "2A2A27"),
		Color(hex: "1A1A1A"),
		Color(hex: "232323"),
	]

	static func palette(for url: URL?) async -> [Color] {
		guard let url else { return Self.fallback }

		let key = url.absoluteString as NSString
		if let cached = Self.cache.object(forKey: key) {
			return cached.colors
		}

		guard let (data, _) = try? await URLSession.shared.data(from: url) else { return Self.fallback }
		guard let colors = Self.dominantColors(from: data) else { return Self.fallback }

		Self.cache.setObject(PaletteBox(colors), forKey: key)
		return colors
	}

	/// Downsamples to a tiny thumbnail, then buckets pixels into coarse RGB bins and returns the most
	/// frequent bins' average colors — cheap, deterministic, and good enough for a soft background
	/// gradient (no need for a full k-means pass).
	private static func dominantColors(from data: Data) -> [Color]? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

		let thumbnailOptions: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceThumbnailMaxPixelSize: 24,
			kCGImageSourceCreateThumbnailWithTransform: true,
		]
		guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }

		let width = cgImage.width
		let height = cgImage.height
		guard width > 0, height > 0 else { return nil }

		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(
			data: &pixels,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else { return nil }

		context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

		// Quantize to 4 bits/channel (16^3 bins) so near-identical colors merge, then keep the most
		// frequent bins' true average color (not the quantized bucket center, for smoother output).
		var bucketSums: [Int: (r: Int, g: Int, b: Int, count: Int)] = [:]

		for pixelIndex in stride(from: 0, to: pixels.count, by: 4) {
			let r = Int(pixels[pixelIndex])
			let g = Int(pixels[pixelIndex + 1])
			let b = Int(pixels[pixelIndex + 2])
			let a = pixels[pixelIndex + 3]
			guard a > 200 else { continue }

			// Skip near-black/near-white pixels — common cover-art letterboxing/margins that would
			// otherwise dominate the palette with a color that reads as "no color" in a mesh gradient.
			let maxChannel = max(r, g, b)
			let minChannel = min(r, g, b)
			if maxChannel < 24 || minChannel > 235 { continue }

			let bucketKey = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
			var entry = bucketSums[bucketKey] ?? (0, 0, 0, 0)
			entry.r += r
			entry.g += g
			entry.b += b
			entry.count += 1
			bucketSums[bucketKey] = entry
		}

		let topBuckets = bucketSums.values.sorted { $0.count > $1.count }.prefix(4)
		guard !topBuckets.isEmpty else { return nil }

		let colors = topBuckets.map { bucket in
			Color(
				red: Double(bucket.r) / Double(bucket.count) / 255,
				green: Double(bucket.g) / Double(bucket.count) / 255,
				blue: Double(bucket.b) / Double(bucket.count) / 255
			)
		}

		// Fewer than 3 distinct dominant colors (e.g. a near-monochrome cover) makes for a flat mesh —
		// pad by repeating so `CoverMeshBackground` always has enough to interpolate across its grid.
		var padded = colors
		while padded.count < 3 {
			padded.append(colors[padded.count % colors.count])
		}
		return padded
	}
}
