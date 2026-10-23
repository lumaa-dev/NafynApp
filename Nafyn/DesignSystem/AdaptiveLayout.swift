// Made by Lumaa

import SwiftUI

/// Layout metrics shared by every screen that adapts to a wider window: the iPhone Duo's inner display
/// today, iPad later. Nothing here branches on device idiom or orientation — screens read the size class
/// (or the container's width) and these values only describe how wide content is allowed to get.
enum DTLayout {
	/// Widest a column of text, rows or a form should grow before it stops stretching.
	static let readableWidth: CGFloat = 720

	/// Widest a grid of cards should grow; wider windows get margins instead of ever-smaller cards.
	static let gridWidth: CGFloat = 1100

	/// Widest the onboarding card and other single-purpose panels should grow.
	static let panelWidth: CGFloat = 520

	/// Cover size on a detail screen's header in a compact vs. a regular-width window.
	static func detailCoverWidth(isRegular: Bool) -> CGFloat {
		isRegular ? 340 : 200
	}
}

extension GridItem {
	/// One adaptive column that holds as many ``MusicCard``s as fit. In a compact-width window this
	/// resolves to the same two columns the old `[.flexible(), .flexible()]` did; wider windows add
	/// columns instead of stretching or stranding fixed-width cards.
	static var musicCard: GridItem {
		GridItem(.adaptive(minimum: 150, maximum: 220), alignment: .top)
	}
}

/// Where a vertical fold splits a view, in that view's own coordinates.
nonisolated private struct FoldSplit: Equatable, Sendable {
	var width: CGFloat
	var minX: CGFloat
	var maxX: CGFloat
}

/// A grid of ``MusicCard``s. Normally an adaptive grid; when an iPhone Duo is partly folded like a book,
/// the fold gets a column gap of its own so no card sits on the hinge and every card stays tappable.
/// Items keep their reading order: the rows just read left half, fold, right half.
///
/// A fold that runs horizontally (the device laid down like a laptop) is left alone: rows are not split.
struct FoldGrid<Content: View>: View {
	/// Space between columns while the fold is splitting the grid.
	private static var columnSpacing: CGFloat { 16 }

	/// Narrowest a card may get beside the fold; matches ``GridItem/musicCard``.
	private static var minimumCardWidth: CGFloat { 150 }

	let alignment: HorizontalAlignment
	let spacing: CGFloat?
	let content: Content

	@State private var split: FoldSplit? = nil

	init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
		self.alignment = alignment
		self.spacing = spacing
		self.content = content()
	}

	var body: some View {
		LazyVGrid(columns: self.columns, alignment: self.alignment, spacing: self.spacing) {
			self.content
		}
		.onGeometryChange(for: FoldSplit?.self) { proxy in
			Self.split(in: proxy)
		} action: { newValue in
			self.split = newValue
		}
	}

	private var columns: [GridItem] {
		guard let split else { return [.musicCard] }

		let spacing = Self.columnSpacing
		let half = min(split.minX, split.width - split.maxX)
		let perSide = max(1, Int((half + spacing) / (Self.minimumCardWidth + spacing)))
		let gap = split.maxX - split.minX

		// a column's spacing is the space after it, so the fold's gap goes after the last left column
		return (0..<(perSide * 2)).map { index in
			GridItem(.flexible(), spacing: index == perSide - 1 ? gap : spacing, alignment: .top)
		}
	}

	private static func split(in proxy: GeometryProxy) -> FoldSplit? {
		guard #available(iOS 27.1, *) else { return nil }

		let folds = proxy.reservedRegions(kind: .division)
		guard let fold = folds.first(where: { $0.frame.height > $0.frame.width }) else { return nil }

		let width = proxy.size.width
		// a fold at (or past) an edge of this grid leaves nothing to split
		guard fold.frame.minX >= Self.minimumCardWidth, width - fold.frame.maxX >= Self.minimumCardWidth else { return nil }
		return FoldSplit(width: width, minX: fold.frame.minX, maxX: fold.frame.maxX)
	}
}

private struct ContentMarginsModifier: ViewModifier {
	let maxWidth: CGFloat

	@State private var margin: CGFloat = 0

	func body(content: Content) -> some View {
		content
			.contentMargins(.horizontal, self.margin, for: .scrollContent)
			.onGeometryChange(for: CGFloat.self) { [maxWidth] proxy in
				max(0, (proxy.size.width - maxWidth) / 2)
			} action: { newValue in
				self.margin = newValue
			}
	}
}

/// Two related panes — a primary and a secondary — laid out by the fold-aware `ArrangementView` on
/// iOS 27.1+: side by side when the window is wider than tall, stacked when taller than wide, and respaced
/// around the fold on an iPhone Duo that is partly open. Below iOS 27.1 there is no fold, so it falls back
/// to a plain `HStack`.
///
/// Must not be placed inside a `ScrollView`, `List`, grid or `NavigationSplitView`, and must not contain a
/// navigation container: give each pane its own scroll view (see ``PaneScroll``).
struct SplitPanes<Primary: View, Secondary: View>: View {
	/// Width the primary pane is capped at in the pre-27.1 `HStack`. `ArrangementView` sizes it itself.
	let fallbackPrimaryWidth: CGFloat?
	let primary: Primary
	let secondary: Secondary

	init(fallbackPrimaryWidth: CGFloat? = nil, @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
		self.fallbackPrimaryWidth = fallbackPrimaryWidth
		self.primary = primary()
		self.secondary = secondary()
	}

	var body: some View {
		if #available(iOS 27.1, *) {
			ArrangementView {
				self.primary
			} secondary: {
				self.secondary
			}
			.arrangementViewStyle(.split)
		} else {
			HStack(alignment: .top, spacing: 32) {
				self.primary
					.frame(maxWidth: self.fallbackPrimaryWidth)

				self.secondary
			}
		}
	}
}

/// A screen with one layout for compact width and a ``SplitPanes`` layout for regular width (iPhone Duo
/// inner display, iPad later). `compact` is the whole screen as one scrolling column; `primary` and
/// `secondary` are the same content divided between two independently scrolling panes.
struct AdaptiveDetail<Compact: View, Primary: View, Secondary: View>: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	let compact: Compact
	let primary: Primary
	let secondary: Secondary

	init(@ViewBuilder compact: () -> Compact, @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
		self.compact = compact()
		self.primary = primary()
		self.secondary = secondary()
	}

	var body: some View {
		if self.horizontalSizeClass == .regular {
			SplitPanes(fallbackPrimaryWidth: DTLayout.detailCoverWidth(isRegular: true) + 40) {
				PaneScroll { self.primary }
			} secondary: {
				PaneScroll { self.secondary }
			}
		} else {
			PaneScroll { self.compact }
				.contentColumn()
		}
	}
}

/// One scrolling column of a detail screen, with the screen's standard padding and edge effect.
struct PaneScroll<Content: View>: View {
	let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		ScrollView {
			self.content
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding()
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
	}
}

extension View {
	/// Centers a `ScrollView`/`List`'s content in a column at most `maxWidth` wide by growing its side
	/// content margins. Margins (rather than a `.frame(maxWidth:)` on the scroll view) keep the scroll
	/// indicator and edge effects on the window's edge. A no-op in any window narrower than `maxWidth`.
	func contentColumn(maxWidth: CGFloat = DTLayout.readableWidth) -> some View {
		self.modifier(ContentMarginsModifier(maxWidth: maxWidth))
	}
}
