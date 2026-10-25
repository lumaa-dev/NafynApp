// Made by Lumaa

import SwiftUI

/// How far the enclosing ``CoverScrollView`` is pulled past its top edge, in points (0 at rest).
///
/// A reference type read only by ``CoverHeader``: updating it on every scroll frame redraws the header,
/// not the whole screen (track lists included).
@Observable
final class CoverStretch {
	var overscroll: CGFloat = 0
}

private struct CoverStretchKey: EnvironmentKey {
	static let defaultValue: CoverStretch? = nil
}

private struct CoverTopInsetKey: EnvironmentKey {
	static let defaultValue: CGFloat = 0
}

private struct CoverMaxHeightKey: EnvironmentKey {
	static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
	/// Tallest the cover may get, as set by ``CoverScrollView`` from its own height: in a pane too short for a
	/// square cover (an iPhone held sideways, half of a half-folded Duo) the cover is cropped to fit instead
	/// of pushing the title below the fold. Never reached in a phone's portrait column.
	var coverMaxHeight: CGFloat? {
		get { self[CoverMaxHeightKey.self] }
		set { self[CoverMaxHeightKey.self] = newValue }
	}

	var coverStretch: CoverStretch? {
		get { self[CoverStretchKey.self] }
		set { self[CoverStretchKey.self] = newValue }
	}

	/// The top safe area *above the navigation bar* (status bar / Dynamic Island) around a ``CoverScrollView``.
	var coverTopInset: CGFloat {
		get { self[CoverTopInsetKey.self] }
		set { self[CoverTopInsetKey.self] = newValue }
	}
}

/// The scroll view of a cover-themed detail screen: the cover's uni-color behind everything, the palette
/// and the overscroll amount shared with the content (`TrackRow`, ``CoverHeader``).
///
/// It ignores the top safe area on purpose: SwiftUI turns a vertical scroll view's top safe area into a
/// content inset, which leaves `backgroundExtensionEffect()` no safe area to extend into on that edge.
/// Ignoring it hands the area back to the content. Only the status bar / Dynamic Island part of it is shared
/// as `\.coverTopInset` for ``CoverHeader`` to hand back to the cover: the navigation bar is left out, so the
/// cover runs up beneath the toolbar and only the area above it is the extension's. The window's top inset is
/// that part exactly; it is capped by a `GeometryReader` *around* the scroll view (`safeAreaInsets` read from
/// inside a vertical scroll view is always 0), which also re-runs it when the window is resized or rotated.
struct CoverScrollView<Content: View>: View {
	var palette: CoverPalette
	@ViewBuilder var content: () -> Content

	@State private var stretch = CoverStretch()

	/// The key window's top safe area: the status bar / Dynamic Island, without the navigation bar.
	private static var statusBarInset: CGFloat {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first(where: \.isKeyWindow)?
			.safeAreaInsets.top ?? 0
	}

	var body: some View {
		GeometryReader { outer in
			ScrollView {
				self.content()
			}
			.ignoresSafeArea(edges: .top)
			.onScrollGeometryChange(for: CGFloat.self) { geometry in
				max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
			} action: { _, overscroll in
				self.stretch.overscroll = overscroll
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.environment(\.coverTopInset, min(Self.statusBarInset, outer.safeAreaInsets.top))
			.environment(\.coverMaxHeight, outer.size.height * 0.7)
		}
		.background(self.palette.background.ignoresSafeArea())
		.environment(\.coverPalette, self.palette)
		.environment(\.coverStretch, self.stretch)
	}
}

/// The top of a cover-themed detail screen: the cover edge to edge with no padding or rounded clipping, running
/// up beneath the toolbar. `backgroundExtensionEffect()` extends it into the status bar / Dynamic Island area
/// above it; below it sits the title block (`details`: album/track name and artist) on a blurred mirror of the
/// cover that fades into the screen's uni-color. Pulled past its top, the header stays pinned to the top of
/// the screen instead of stretching.
///
/// The bottom is *not* `backgroundExtensionEffect()`: its copy there rendered darker than the cover's last row,
/// leaving a hard step at the seam, and nothing in the modifier tunes that. A bottom `safeAreaInset` also made
/// the effect size its copy from the container's whole safe area (tab bar included), spilling behind the list.
/// The mirror here starts on the cover's own bottom row, so the seam is continuous. Must sit directly in a
/// ``CoverScrollView``'s content.
struct CoverHeader<Details: View>: View {
	var url: URL?
	var palette: CoverPalette
	@ViewBuilder var details: () -> Details

	@Environment(\.coverStretch) private var stretch

	/// The status bar / Dynamic Island area. It is handed back to the cover as a transparent top
	/// `safeAreaInset`, which is what the extension fills there.
	@Environment(\.coverTopInset) private var topInset

	@Environment(\.coverMaxHeight) private var maxCoverHeight

	var body: some View {
		let overscroll = self.stretch?.overscroll ?? 0

		VStack(spacing: 0) {
			Color.clear
				.aspectRatio(1, contentMode: .fit)
				.frame(maxWidth: .infinity)
				.frame(maxHeight: self.maxCoverHeight)
				.overlay {
					GeometryReader { proxy in
						CoverImage(url: self.url, cornerRadius: 0)
							.frame(width: proxy.size.width, height: proxy.size.height)
							.clipped()
							.backgroundExtensionEffect()
					}
				}
				.safeAreaInset(edge: .top, spacing: 0) {
					Color.clear.frame(height: self.topInset)
				}
				.safeAreaInset(edge: .bottom, spacing: 0) {
					VStack(alignment: .leading, spacing: 2) {
						self.details()
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal)
					.padding(.top, 15)
					.padding(.bottom, 12)
					.background {
						LinearGradient(
							stops: [
								.init(color: self.palette.background.opacity(0.1), location: 0),
								.init(color: self.palette.background.opacity(0.6), location: 0.25),
								.init(color: self.palette.background.opacity(0.9), location: 0.45),
								.init(color: self.palette.background, location: 1),
							],
							startPoint: .top,
							endPoint: .bottom
						)
					}
				}
		}
		// The top copy of the effect is cut to the status bar strip, the one part of it that is on screen.
		.clipped()
		// Pulled down, the content moves down by `overscroll`; moving the header up by as much keeps it
		// where it is (the extension stays attached, nothing scales or blurs differently).
		.offset(y: -overscroll)
	}
}
