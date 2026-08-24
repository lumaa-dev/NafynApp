// Made by Lumaa

import SwiftUI

extension EnvironmentValues {
	/// A tab-root-owned `@Namespace` for `.matchedTransitionSource`/`.navigationTransition(.zoom(sourceID:in:))`,
	/// so nested cards can zoom into their detail view without prop-drilling the namespace down manually.
	@Entry var zoomNamespace: Namespace.ID? = nil
}
