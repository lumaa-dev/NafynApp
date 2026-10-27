// Made by Lumaa

import SwiftUI

/// Shimmering placeholder block, the base unit every skeleton shape composes from.
private struct SkeletonBlock: View {
	var cornerRadius: CGFloat = 6
	@State private var phase: CGFloat = -1.4

	var body: some View {
		RoundedRectangle(cornerRadius: self.cornerRadius)
			.fill(DTColor.surfaceSelect)
			.overlay(
				GeometryReader { geo in
					LinearGradient(
						colors: [.clear, DTColor.textPrimary.opacity(0.14), .clear],
						startPoint: .leading,
						endPoint: .trailing
					)
					.frame(width: geo.size.width * 0.6)
					.offset(x: self.phase * geo.size.width)
				}
				.clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
			)
			.onAppear {
				withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
					self.phase = 1.4
				}
			}
	}
}

/// A rounded-rect skeleton bar, typically standing in for a line of text or a square cover.
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

/// A circular skeleton, standing in for an artist's round cover art.
struct SkeletonCircle: View {
	var diameter: CGFloat

	var body: some View {
		SkeletonBlock(cornerRadius: self.diameter / 2)
			.frame(width: self.diameter, height: self.diameter)
	}
}

/// Mirrors ``TrackRow``'s "cover • title • subtitle • duration" layout.
struct SkeletonTrackRow: View {
	var showsCover: Bool = true
	var verticalPadding: CGFloat = 2

	var body: some View {
		HStack(spacing: 12) {
			if self.showsCover {
				SkeletonBar(width: 44, height: 44, cornerRadius: 6)
			}

			VStack(alignment: .leading, spacing: 6) {
				SkeletonBar(width: 160, height: 14)
				SkeletonBar(width: 100, height: 12)
			}

			Spacer()

			SkeletonBar(width: 28, height: 10)
		}
		.padding(.vertical, self.verticalPadding)
	}
}

/// Mirrors ``MusicCard``'s `.highlight`/`.row` layouts.
struct SkeletonMusicCard: View {
	enum ViewType {
		case highlight
		case row
	}

	var type: Self.ViewType = .highlight

	var body: some View {
		switch self.type {
			case .highlight:
				VStack(alignment: .leading) {
					Color.clear
						.aspectRatio(1.0, contentMode: .fit)
						.overlay { SkeletonBlock(cornerRadius: 10) }
					SkeletonBar(width: 130, height: 16)
					SkeletonBar(width: 90, height: 14)
				}
				.frame(maxWidth: .infinity, alignment: .topLeading)
			case .row:
				HStack {
					SkeletonBar(width: 60, height: 60, cornerRadius: 10)

					VStack(alignment: .leading, spacing: 6) {
						SkeletonBar(width: 150, height: 16)
						SkeletonBar(width: 100, height: 14)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
		}
	}
}

/// A vertical run of ``SkeletonTrackRow``, for lists still loading their first page.
struct SkeletonTrackRows: View {
	var showsCover: Bool = true
	var count: Int = 8

	var body: some View {
		ForEach(0..<self.count, id: \.self) { _ in
			SkeletonTrackRow(showsCover: self.showsCover)
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

/// Default skeleton for ``AsyncContentView``: a detail screen's cover header plus a handful of track rows.
struct SkeletonDetailScreen: View {
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .center, spacing: 10) {
					SkeletonBar(width: 200, height: 200, cornerRadius: 10)
					SkeletonBar(width: 180, height: 20)
					SkeletonBar(width: 120, height: 15)
				}
				.frame(maxWidth: .infinity, alignment: .center)
				.padding(.top, 24)

				VStack(alignment: .leading, spacing: 0) {
					SkeletonTrackRows(count: 6)
				}
			}
			.padding()
		}
	}
}

/// Skeleton for text-heavy screens (e.g. lyrics), a stack of variable-width lines.
struct SkeletonTextLines: View {
	var count: Int = 10

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			ForEach(0..<self.count, id: \.self) { i in
				SkeletonBar(width: i.isMultiple(of: 3) ? 220 : 160, height: 20)
			}
		}
		.padding()
	}
}

/// Skeleton for simple form/settings screens, a stack of labeled-row-shaped bars.
struct SkeletonFormRows: View {
	var count: Int = 5

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			ForEach(0..<self.count, id: \.self) { _ in
				HStack {
					SkeletonBar(width: 100, height: 14)
					Spacer()
					SkeletonBar(width: 140, height: 14)
				}
			}
		}
		.padding()
	}
}
