// Made by Lumaa

import SwiftUI

/// A cover-themed detail screen (``CoverScrollView`` + ``CoverHeader``) that adapts to its window.
///
/// - One column, as on a phone held upright: the header, then `compact` below it. Also used by a tall regular
///   window (iPad in portrait, an unfolded Duo held upright), where the content is capped to a readable width.
/// - Two panes, when the window has room for them (see ``DTLayout/hasRoomForPanes(horizontal:vertical:)``) and
///   is either wider than tall or partly folded: the header and `primary` in a pane of their own, `secondary`
///   (the actions and the track list) in the other, through ``SplitPanes`` so the Duo's fold is respected.
///   An iPhone held sideways lands here too, with a cover cropped to fit (``EnvironmentValues/coverMaxHeight``).
///
/// `compact`, `primary` and `secondary` are the same content divided differently; each is laid out in a padded
/// column below the header.
struct AdaptiveCoverDetail<Header: View, Compact: View, Primary: View, Secondary: View>: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	let palette: CoverPalette
	let spacing: CGFloat
	let header: Header
	let compact: Compact
	let primary: Primary
	let secondary: Secondary

	init(
		palette: CoverPalette,
		spacing: CGFloat = 16,
		@ViewBuilder header: () -> Header,
		@ViewBuilder compact: () -> Compact,
		@ViewBuilder primary: () -> Primary,
		@ViewBuilder secondary: () -> Secondary
	) {
		self.palette = palette
		self.spacing = spacing
		self.header = header()
		self.compact = compact()
		self.primary = primary()
		self.secondary = secondary()
	}

	var body: some View {
		GeometryReader { proxy in
			if self.showsPanes(in: proxy) {
				self.panes
			} else {
				self.column
			}
		}
		// also fills the gap between the panes (the fold, or the pre-27.1 stack's spacing)
		.background(self.palette.background.ignoresSafeArea())
	}

	private var column: some View {
		CoverScrollView(palette: self.palette) {
			VStack(alignment: .leading, spacing: 16) {
				self.header

				self.padded(self.compact)
			}
		}
		.scrollEdgeEffectHidden()
	}

	private var panes: some View {
		SplitPanes {
			CoverScrollView(palette: self.palette) {
				VStack(alignment: .leading, spacing: 16) {
					self.header

					self.padded(self.primary)
				}
			}
			.scrollEdgeEffectHidden()
		} secondary: {
			// Plain scroll view: it has no cover to run beneath the toolbar, so it keeps the soft edge effect
			// to stay legible where rows scroll under it.
			ScrollView {
				self.padded(self.secondary)
					.padding(.top)
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.environment(\.coverPalette, self.palette)
		}
	}

	private func padded<Content: View>(_ content: Content) -> some View {
		VStack(alignment: .leading, spacing: self.spacing) {
			content
		}
		.frame(maxWidth: DTLayout.readableWidth, alignment: .leading)
		.frame(maxWidth: .infinity)
		.padding(.horizontal)
		.padding(.bottom)
	}

	/// Panes need room (a wide window or a short one) and a reason to sit side by side: the window is wider
	/// than tall, or a Duo is partly folded, where `ArrangementView` stacks or splits them around the fold.
	/// A tall, flat window (iPad in portrait) keeps one column rather than a cover pane over a cramped list.
	private func showsPanes(in proxy: GeometryProxy) -> Bool {
		guard DTLayout.hasRoomForPanes(horizontal: self.horizontalSizeClass, vertical: self.verticalSizeClass) else { return false }
		return proxy.size.width > proxy.size.height || Self.isPartlyFolded(proxy)
	}

	private static func isPartlyFolded(_ proxy: GeometryProxy) -> Bool {
		if #available(iOS 27.1, *) {
			return !proxy.reservedRegions(kind: .division).isEmpty
		}
		return false
	}
}
