// Made by Lumaa

import SwiftUI

/// Which screens currently have a card on screen that can zoom into them, so the screen it opens can zoom out
/// of that card's cover (as Apple Music's albums do) instead of every push in the app zooming from the middle
/// of the screen.
///
/// A zoom transition needs the source and the destination to agree on an ID. The card uses the path it opens
/// as that ID and registers while it is visible; the destination only asks for the zoom when a card for its
/// path is registered at the moment it is pushed, so a push from anywhere else (an artist link, a deep link, a
/// notification) keeps the standard transition. Nothing here touches taps: the card's own `NavigationLink`
/// stays the only thing that reacts to them.
@MainActor
enum CardZoom {
	private static var visible: [Navigator.Paths: Int] = [:]

	static func register(_ path: Navigator.Paths?) {
		guard let path else { return }
		self.visible[path, default: 0] += 1
	}

	static func unregister(_ path: Navigator.Paths?) {
		guard let path, let count = self.visible[path] else { return }
		self.visible[path] = count > 1 ? count - 1 : nil
	}

	static func hasSource(for path: Navigator.Paths) -> Bool {
		self.visible[path] != nil
	}
}

/// Wraps a pushed destination, adding the zoom transition when a card opened it.
struct CardZoomDestination<Content: View>: View {
	@Environment(\.zoomNamespace) private var namespace: Namespace.ID?

	let path: Navigator.Paths
	let content: Content

	/// Decided once, when the screen is pushed: cards coming and going later must not swap the view tree of
	/// a screen that is already open.
	@State private var zooms: Bool

	init(path: Navigator.Paths, @ViewBuilder content: () -> Content) {
		self.path = path
		self.content = content()
		self._zooms = State(initialValue: CardZoom.hasSource(for: path))
	}

	var body: some View {
		if self.zooms, let namespace = self.namespace {
			self.content
				.navigationTransition(.zoom(sourceID: self.path, in: namespace))
		} else {
			self.content
		}
	}
}

extension View {
	/// Marks a card's cover as the origin of the zoom into `destination`.
	@ViewBuilder
	func cardZoomSource(_ destination: Navigator.Paths?, in namespace: Namespace.ID?, cornerRadius: CGFloat) -> some View {
		if let destination, let namespace {
			self
				.matchedTransitionSource(id: destination, in: namespace) { source in
					source.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
				}
		} else {
			self
		}
	}
}
