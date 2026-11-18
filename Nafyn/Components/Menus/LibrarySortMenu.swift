// Made by Lumaa

import SwiftUI
import Safyn

/// The sort button of the Tracks and Albums lists: a menu with one checked entry, like the Requests filter. The
/// icon fills while the order is not the default (recently added).
struct LibrarySortMenu: View {
	@Binding var sort: LibrarySort

	var body: some View {
		Menu {
			Picker(String(localized: "sort"), selection: self.$sort) {
				ForEach(LibrarySort.allCases) { option in
					Label(option.title, systemImage: option.symbol)
						.tag(option)
				}
			}
			.pickerStyle(.inline)
		} label: {
			Label(String(localized: "sort"), systemImage: self.sort == .added ? "arrow.up.arrow.down.circle" : "arrow.up.arrow.down.circle.fill")
				.labelStyle(.iconOnly)
		}
		.tint(Color.primary)
	}
}
