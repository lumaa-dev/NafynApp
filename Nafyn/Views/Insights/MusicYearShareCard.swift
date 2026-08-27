// Made by Lumaa

import SwiftUI
import Safyn

/// The square card rendered into an image for sharing a year's highlights.
///
/// Rendered off-screen through `ImageRenderer`, which draws only what it can resolve synchronously —
/// `AsyncImage` would come out blank, so cover art is fetched up front by ``loadCovers(for:)`` and
/// handed in as already-decoded images.
struct MusicYearShareCard: View {
	let insights: YearlyInsights
	#if canImport(UIKit)
	let covers: [UIImage]
	#else
	let covers: [Never]
	#endif

	private static let side: CGFloat = 400

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 2) {
				Text(String(localized: "music-year"))
					.font(DTFont.system(14, weight: .medium))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))

				Text(String(self.insights.year))
					.font(DTFont.serif(56))
					.foregroundStyle(DTColor.textPrimary)
			}

			self.coverStrip

			VStack(alignment: .leading, spacing: 10) {
				self.line(
					value: InsightsFormat.minutes(self.insights.totals.totalMinutes),
					caption: String(localized: "insights-total-listening")
				)

				if let topTrack = self.insights.top.track?.first {
					self.line(value: topTrack.title ?? topTrack.entityId, caption: String(localized: "insights-top-track"))
				}

				if let topArtist = self.insights.top.artist?.first {
					self.line(value: topArtist.title ?? topArtist.entityId, caption: String(localized: "insights-top-artist"))
				}
			}

			Spacer(minLength: 0)

			Text("Nafyn")
				.font(DTFont.serifItalic(20))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))
		}
		.padding(28)
		.frame(width: Self.side, height: Self.side, alignment: .leading)
		.background(DTColor.background)
	}

	@ContentBuilder
	private var coverStrip: some View {
		#if canImport(UIKit)
		if !self.covers.isEmpty {
			HStack(spacing: 8) {
				ForEach(Array(self.covers.prefix(4).enumerated()), id: \.offset) { _, cover in
					Image(uiImage: cover)
						.resizable()
						.scaledToFill()
						.frame(width: 74, height: 74)
						.clipShape(RoundedRectangle(cornerRadius: 10))
				}
			}
		}
		#endif
	}

	@ContentBuilder
	private func line(value: String, caption: String) -> some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(caption)
				.font(DTFont.system(11))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

			Text(value)
				.font(DTFont.serif(24))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
		}
	}

	#if canImport(UIKit)
	/// Downloads the artwork for the card's cover strip: the year's top tracks, falling back to its top
	/// albums when tracks carry no cover.
	static func loadCovers(for insights: YearlyInsights) async -> [UIImage] {
		let urls = ((insights.top.track ?? []) + (insights.top.album ?? []))
			.compactMap { $0.cover.flatMap(URL.init(string:)) }
			.prefix(4)

		var images: [UIImage] = []
		for url in urls {
			guard
				let (data, _) = try? await URLSession.shared.data(from: url),
				let image = UIImage(data: data)
			else { continue }
			images.append(image)
		}
		return images
	}
	#endif
}
