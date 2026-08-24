// Made by Lumaa

import SwiftUI

protocol Viewable {
	var label: String { get }
	var symbol: String { get }
}

protocol Screeny: Hashable {
	var view: AnyView { get }
}

// - Extensions

extension Viewable {
	@ContentBuilder
	var view: some View {
		Label(self.label, systemImage: self.symbol)
	}
}
