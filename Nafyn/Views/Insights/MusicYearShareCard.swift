// Made by Lumaa

import SwiftUI
import Safyn

/// A period-agnostic snapshot of what a recap share card shows, decoupled from `YearlyInsights`/
/// `MonthlyInsights` directly so one card view serves both.
struct RecapSummary {
	/// "September" (month name only, no year) for a monthly recap, or "2026" for a yearly one.
	let title: String
	let totalMinutes: Int
	/// Up to 3 top artists.
	let topArtists: [RankedEntity]
	/// Up to 3 top tracks.
	let topTracks: [RankedEntity]
	/// Up to 3 top albums.
	let topAlbums: [RankedEntity]

	init(yearly: YearlyInsights) {
		self.title = String(yearly.year)
		self.totalMinutes = yearly.totals.totalMinutes
		self.topArtists = Array((yearly.top.artist ?? []).prefix(3))
		self.topTracks = Array((yearly.top.track ?? []).prefix(3))
		self.topAlbums = Array((yearly.top.album ?? []).prefix(3))
	}

	init(monthly: MonthlyInsights) {
		let parts = monthly.month.split(separator: "-")
		let month = parts.count == 2 ? Int(parts[1]) ?? 1 : 1
		self.title = InsightsFormat.monthName(month)
		self.totalMinutes = monthly.totals.totalMinutes
		self.topArtists = Array((monthly.top.artist ?? []).prefix(3))
		self.topTracks = Array((monthly.top.track ?? []).prefix(3))
		self.topAlbums = Array((monthly.top.album ?? []).prefix(3))
	}
}

/// The card rendered into an image for sharing a recap's highlights — the same card serves both the monthly and
/// yearly recaps, driven entirely by ``RecapSummary``. 9:16, 360 x 640 points rendered at 3x: 1080 x 1920, like
/// every image Nafyn shares (DESIGN.md "Sharing": Instagram / Snapchat stories).
///
/// Rendered off-screen through `ImageRenderer`, which draws only what it can resolve synchronously —
/// `AsyncImage` would come out blank, so cover art is fetched up front by ``loadCovers(for:)`` and
/// handed in as already-decoded images.
struct MusicYearShareCard: View {
	let summary: RecapSummary
	#if canImport(UIKit)
	let covers: [String: UIImage]
	#else
	let covers: [String: Never]
	#endif

	/// The card's size in points, the same as ``ShareCardView``'s.
	static let size = CGSize(width: 360, height: 640)
	private static let padding: CGFloat = 28
	private static let thumbnailSpacing: CGFloat = 14
	/// Three covers side by side across the card's inner width.
	private static let thumbnailSide: CGFloat = (size.width - padding * 2 - thumbnailSpacing * 2) / 3

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline) {
				Text(self.summary.title)
					.font(DTFont.serif(56))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)
					.minimumScaleFactor(0.5)
					.frame(maxWidth: .infinity, alignment: .leading)

				Text(String("Nafyn"))
					.font(DTFont.serifItalic(16))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)
			}

			Text(String(localized: "\(self.summary.totalMinutes)-minutes"))
				.font(DTFont.system(15))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.padding(.bottom, 24)

			self.thumbnails
				.padding(.bottom, 12)

			self.list

			Spacer(minLength: 0)
		}
		// a story's top and bottom sit under the app's own controls: the content keeps clear of both edges
		.padding(.horizontal, Self.padding)
		.padding(.vertical, Self.padding * 2)
		.frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
		.background(DTColor.background)
		.environment(\.colorScheme, .dark)
	}

	// MARK: - Text-only ranked lists

	@ContentBuilder
	private var list: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("top-artists")
				.font(DTFont.serifItalic(23))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.padding(.top, 12)

			ForEach(self.summary.topArtists, id: \.entityId) { entity in
				self.row(entity)
			}

			Text("top-tracks")
				.font(DTFont.serifItalic(23))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.padding(.top, 12)

			ForEach(self.summary.topTracks, id: \.entityId) { entity in
				self.row(entity)
			}

			Text("top-albums")
				.font(DTFont.serifItalic(23))
				.foregroundStyle(DTColor.textPrimary)
				.lineLimit(1)
				.padding(.top, 12)

			ForEach(self.summary.topAlbums, id: \.entityId) { entity in
				self.row(entity)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ContentBuilder
	private func row(_ entity: RankedEntity) -> some View {
		Text(entity.title ?? entity.entityId)
			.font(DTFont.system(16))
			.foregroundStyle(DTColor.textPrimary)
			.lineLimit(1)
	}

	// MARK: - The #1 of each kind, side by side

	@ContentBuilder
	private var thumbnails: some View {
		#if canImport(UIKit)
		HStack(spacing: Self.thumbnailSpacing) {
			self.thumbnail(for: self.summary.topArtists.first, height: Self.thumbnailSide, shape: AnyShape(.circle))
			self.thumbnail(for: self.summary.topTracks.first, height: Self.thumbnailSide, shape: AnyShape(RoundedRectangle(cornerRadius: 10)))
			self.thumbnail(for: self.summary.topAlbums.first, height: Self.thumbnailSide, shape: AnyShape(RoundedRectangle(cornerRadius: 10)))
		}
		#endif
	}

	#if canImport(UIKit)
	@ContentBuilder
	private func thumbnail(for entity: RankedEntity?, height: CGFloat, shape: AnyShape) -> some View {
		if let entity, let image = self.covers[entity.entityId] {
			Image(uiImage: image)
				.resizable()
				.scaledToFill()
				.frame(width: height, height: height)
				.clipShape(shape)
		} else {
			shape
				.fill(DTColor.surfaceSelect)
				.frame(width: height, height: height)
		}
	}

	/// Downloads the artwork for the card's 3 big thumbnails: the #1 artist/track/album, keyed by
	/// `entityId` so a shared entity (unlikely across kinds, but naturally deduped) is fetched once.
	///
	/// All up-to-9 unique covers (3 artists + 3 tracks + 3 albums) are fetched concurrently via a
	/// `TaskGroup` rather than a serial loop.
	static func loadCovers(for summary: RecapSummary) async -> [String: UIImage] {
		let entities = summary.topArtists + summary.topTracks + summary.topAlbums
		var seen = Set<String>()
		let unique = entities.filter { seen.insert($0.entityId).inserted }

		return await withTaskGroup(of: (String, UIImage?).self) { group in
			for entity in unique {
				group.addTask {
					guard let url = entity.cover.flatMap(URL.init(string:)), let data = await CoverArtLoader.shared.contents(of: url), let image = UIImage(data: data) else { return (entity.entityId, nil) }
					return (entity.entityId, image)
				}
			}

			var result: [String: UIImage] = [:]
			for await (id, image) in group {
				if let image { result[id] = image }
			}
			return result
		}
	}
	#endif
}
