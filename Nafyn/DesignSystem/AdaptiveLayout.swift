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

	/// Widest a cover may get next to other content in a window too short for a large one (an iPhone held
	/// sideways).
	static let shortWindowCoverWidth: CGFloat = 200

	/// Whether a window has room for two side-by-side panes: it is wide (iPhone Duo inner display, iPad,
	/// a Pro Max held sideways) or it is short, i.e. an iPhone held sideways, where one tall column would
	/// leave most of the width empty and little height to scroll in.
	static func hasRoomForPanes(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> Bool {
		horizontal == .regular || vertical == .compact
	}

	/// Cover size on a detail screen's header: large in a regular-width, regular-height window, small
	/// everywhere else (a phone's portrait column, or any window that is short).
	static func detailCoverWidth(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> CGFloat {
		horizontal == .regular && vertical != .compact ? 340 : shortWindowCoverWidth
	}
}

/// The square cover at the top of a detail screen, sized for the window it is in (see
/// ``DTLayout/detailCoverWidth(horizontal:vertical:)``) and centered in its column.
struct DetailCover: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	let url: URL?

	var body: some View {
		CoverImage(url: self.url)
			.aspectRatio(1.0, contentMode: .fit)
			.frame(maxWidth: DTLayout.detailCoverWidth(horizontal: self.horizontalSizeClass, vertical: self.verticalSizeClass))
			.frame(maxWidth: .infinity)
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

	/// A fixed number of columns instead of as many as fit.
	let columnCount: Int?
	let content: Content

	@State private var split: FoldSplit? = nil

	init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, columns columnCount: Int? = nil, @ViewBuilder content: () -> Content) {
		self.alignment = alignment
		self.spacing = spacing
		self.columnCount = columnCount
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
		guard let split else {
			guard let columnCount else { return [.musicCard] }
			return Array(repeating: GridItem(.flexible(), spacing: self.spacing, alignment: .top), count: columnCount)
		}

		let spacing = Self.columnSpacing
		let half = min(split.minX, split.width - split.maxX)
		// a fixed count is split over both sides of the fold; otherwise as many columns as fit on each
		let perSide = self.columnCount.map { max(1, ($0 + 1) / 2) } ?? max(1, Int((half + spacing) / (Self.minimumCardWidth + spacing)))
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
/// around the fold on an iPhone Duo that is partly open.
///
/// `ArrangementView` treats a short, unfolded window like a closed Duo held sideways and shows only the
/// primary pane. So an iPhone held sideways (compact vertical size class, no fold) and any device below
/// iOS 27.1 get a plain `HStack` instead, where both panes always show, side by side.
///
/// Must not be placed inside a `ScrollView`, `List`, grid or `NavigationSplitView`, and must not contain a
/// navigation container: give each pane its own scroll view (see ``PaneScroll``).
struct SplitPanes<Primary: View, Secondary: View>: View {
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	/// Whether the device is partly folded: a `division` reserved region (the fold) is active over this view.
	@State private var isFolded = false

	/// Width the primary pane is capped at in the `HStack`. `ArrangementView` sizes it itself; without a cap
	/// the `HStack` gives both panes half the width.
	let fallbackPrimaryWidth: CGFloat?
	let primary: Primary
	let secondary: Secondary

	init(fallbackPrimaryWidth: CGFloat? = nil, @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
		self.fallbackPrimaryWidth = fallbackPrimaryWidth
		self.primary = primary()
		self.secondary = secondary()
	}

	/// The fold needs `ArrangementView`; so does any window tall enough for it to place both panes.
	private var usesArrangement: Bool {
		self.isFolded || self.verticalSizeClass != .compact
	}

	var body: some View {
		Group {
			if #available(iOS 27.1, *), self.usesArrangement {
				ArrangementView {
					self.primary
				} secondary: {
					self.secondary
				}
				.arrangementViewStyle(.split)
			} else {
				HStack(alignment: .top, spacing: 32) {
					self.primary
						.frame(maxWidth: self.fallbackPrimaryWidth ?? .infinity, maxHeight: .infinity)

					self.secondary
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
		.onGeometryChange(for: Bool.self) { proxy in
			if #available(iOS 27.1, *) {
				return !proxy.reservedRegions(kind: .division).isEmpty
			}
			return false
		} action: { newValue in
			self.isFolded = newValue
		}
	}
}

/// A screen with one layout for compact width and a ``SplitPanes`` layout for regular width (iPhone Duo
/// inner display, iPad later). `compact` is the whole screen as one scrolling column; `primary` and
/// `secondary` are the same content divided between two independently scrolling panes.
struct AdaptiveDetail<Compact: View, Primary: View, Secondary: View>: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	let compact: Compact
	let primary: Primary
	let secondary: Secondary

	init(@ViewBuilder compact: () -> Compact, @ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
		self.compact = compact()
		self.primary = primary()
		self.secondary = secondary()
	}

	var body: some View {
		if DTLayout.hasRoomForPanes(horizontal: self.horizontalSizeClass, vertical: self.verticalSizeClass) {
			SplitPanes(fallbackPrimaryWidth: DTLayout.detailCoverWidth(horizontal: .regular, vertical: .regular) + 40) {
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
