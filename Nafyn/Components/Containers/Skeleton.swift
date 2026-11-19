// Made by Lumaa

import SwiftUI

// DESIGN.md "Skeleton loading": a skeleton is the screen itself, drawn with placeholder data and redacted
// (`redacted(reason: .placeholder)`), so its shapes are the loaded screen's; dark gray, and never animated (no
// blinking, sliding gradient or pulsing opacity). A screen loaded through ``AsyncContentView`` passes its own
// placeholder value (see `Placeholders.swift`); the views below are the skeletons of shared components, for lists
// and the screens that have no placeholder of their own.

extension EnvironmentValues {
	/// `true` inside a skeleton: the content shows placeholder data, so it starts nothing (no fetch, no feedback
	/// event, no paginator) - its real self takes its place once loaded.
	@Entry var isSkeleton: Bool = false
}

extension View {
	/// This view as a skeleton: placeholder text and covers in dark gray, nothing tappable (toolbar buttons stay, disabled).
	func skeleton(_ active: Bool = true) -> some View {
		self
			.redacted(reason: active ? .placeholder : [])
			.disabled(active)
			.environment(\.isSkeleton, active)
			.accessibilityHidden(active)
	}
}

/// A flat dark-gray block, the base unit of a skeleton shape that has no text to redact (a cover, a bar).
private struct SkeletonBlock: View {
	var cornerRadius: CGFloat = 6

	var body: some View {
		RoundedRectangle(cornerRadius: self.cornerRadius)
			.fill(DTColor.surfaceSelect)
	}
}

/// A rounded-rect skeleton bar, standing in for something that is not text (a progress bar, a chart).
struct SkeletonBar: View {
	var width: CGFloat? = nil
	var height: CGFloat = 14
	var cornerRadius: CGFloat = 6

	var body: some View {
		SkeletonBlock(cornerRadius: self.cornerRadius)
			.frame(width: self.width, height: self.height)
			.frame(maxWidth: self.width == nil ? .infinity : nil)
	}
}

/// A ``TrackRow`` with placeholder text, redacted: the same cover, title, subtitle and duration as a loaded row.
struct SkeletonTrackRow: View {
	var showsCover: Bool = true
	var verticalPadding: CGFloat = 2
	/// Varies the title's length from row to row, like real titles.
	var variant: Int = 0

	/// Never loaded: a redacted ``CoverImage`` only draws its shape.
	static let placeholderCover = URL(string: "nafyn-placeholder://cover")

	private static let titles = ["Placeholder title", "A longer placeholder title", "Placeholder", "Title of a track"]
	private static let subtitles = ["Artist name", "Placeholder artist", "Artist"]

	var body: some View {
		TrackRow(
			coverURL: self.showsCover ? Self.placeholderCover : nil,
			title: Self.titles[self.variant % Self.titles.count],
			subtitle: Self.subtitles[self.variant % Self.subtitles.count],
			duration: 215,
			verticalPadding: self.verticalPadding
		)
		.skeleton()
	}
}

/// Mirrors ``MusicCard``'s `.highlight`/`.row` layouts with redacted placeholder text.
struct SkeletonMusicCard: View {
	enum ViewType {
		case highlight
		case row
	}

	var type: Self.ViewType = .highlight

	var body: some View {
		Group {
			switch self.type {
				case .highlight:
					VStack(alignment: .leading) {
						Color.clear
							.aspectRatio(1.0, contentMode: .fit)
							.overlay { SkeletonBlock(cornerRadius: 10) }
						Text(verbatim: "Placeholder title")
							.font(DTFont.serif(18))
							.lineLimit(1)
						Text(verbatim: "Artist name")
							.font(DTFont.serif(15))
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .topLeading)
				case .row:
					HStack {
						SkeletonBlock(cornerRadius: 10)
							.frame(width: 60, height: 60)

						VStack(alignment: .leading, spacing: 2) {
							Text(verbatim: "Placeholder title")
								.font(DTFont.serif(18))
								.lineLimit(1)
							Text(verbatim: "Artist name")
								.font(DTFont.serif(15))
								.lineLimit(1)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
			}
		}
		.skeleton()
	}
}

/// A vertical run of ``SkeletonTrackRow``, for lists still loading their first page.
struct SkeletonTrackRows: View {
	var showsCover: Bool = true
	var count: Int = 8

	var body: some View {
		ForEach(0..<self.count, id: \.self) { index in
			SkeletonTrackRow(showsCover: self.showsCover, variant: index)
		}
	}
}

/// A grid of ``SkeletonMusicCard``, for ``FoldGrid`` screens still loading their first page.
struct SkeletonMusicGrid: View {
	var count: Int = 6

	var body: some View {
		FoldGrid(spacing: 16) {
			ForEach(0..<self.count, id: \.self) { _ in
				SkeletonMusicCard(type: .highlight)
			}
		}
	}
}

/// The skeleton of a cover-themed detail screen (``AdaptiveCoverDetail``) that has no placeholder of its own: the
/// cover edge to edge with the title on it, Play / Shuffle, then track rows.
struct SkeletonDetailScreen: View {
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Color.clear
					.aspectRatio(1, contentMode: .fit)
					.frame(maxWidth: .infinity)
					.frame(maxHeight: 520)
					.overlay { SkeletonBlock(cornerRadius: 0) }
					.overlay(alignment: .bottomLeading) {
						VStack(alignment: .leading, spacing: 2) {
							Text(verbatim: "Placeholder title")
								.font(DTFont.serif(31))
							Text(verbatim: "Artist name")
								.font(DTFont.serifItalic(20))
						}
						.padding(.horizontal)
						.padding(.bottom, 12)
					}

				VStack(alignment: .leading, spacing: 16) {
					HStack {
						Label(String(localized: "play"), systemImage: "play.fill")
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.background(Capsule().fill(DTColor.surfaceSelect))
						Label(String(localized: "shuffle"), systemImage: "shuffle")
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.background(Capsule().fill(DTColor.surfaceSelect))
					}

					VStack(alignment: .leading, spacing: 0) {
						SkeletonTrackRows(count: 6)
					}
				}
				.frame(maxWidth: DTLayout.readableWidth, alignment: .leading)
				.frame(maxWidth: .infinity)
				.padding(.horizontal)
			}
		}
		.scrollDisabled(true)
		.ignoresSafeArea(edges: .top)
		.skeleton()
	}
}

/// Skeleton for text-heavy screens (lyrics): lines of lyrics-sized placeholder text, redacted.
struct SkeletonTextLines: View {
	var count: Int = 10

	private static let lines = ["A placeholder line of lyrics", "Placeholder words", "Another line of the song here"]

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			ForEach(0..<self.count, id: \.self) { i in
				Text(verbatim: Self.lines[i % Self.lines.count])
					.font(DTFont.serif(32).bold())
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding()
		.skeleton()
	}
}

/// Skeleton for simple form/settings screens: label and value rows, redacted.
struct SkeletonFormRows: View {
	var count: Int = 5

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			ForEach(0..<self.count, id: \.self) { _ in
				HStack {
					Text(verbatim: "Setting name")
					Spacer()
					Text(verbatim: "Its value")
				}
				.font(DTFont.system(17))
			}
		}
		.padding()
		.skeleton()
	}
}
