// Made by Lumaa

import SwiftUI

/// The "View" actions of a menu (DESIGN.md "Context Menus": actions that begin with the same word are nested):
/// two or more become one "View" submenu (View > Album | Artist | Track), a lone one stays a plain "View Album".
/// Every item, and the submenu itself, is tinted like the rest of the menu.
struct ViewMenuItems: View {
	/// One place a "View" item leads to.
	struct Target: Identifiable {
		let id: String
		/// The label when it is the only "View" item ("View Artist").
		let title: String
		/// The label inside the "View" submenu ("Artist").
		let nestedTitle: String
		let systemImage: String
		let action: () -> Void

		/// The MusicBrainz album. `catalog` says so in its lone label, where the menu belongs to a library item.
		static func album(catalog: Bool = false, _ action: @escaping () -> Void) -> Target {
			Target(
				id: "album",
				title: catalog ? String(localized: "view-catalog-album") : String(localized: "view-album"),
				nestedTitle: String(localized: "album"),
				systemImage: catalog ? "opticaldisc" : "square.stack",
				action: action
			)
		}

		static func artist(_ action: @escaping () -> Void) -> Target {
			Target(id: "artist", title: String(localized: "view-artist"), nestedTitle: String(localized: "artist"), systemImage: "person", action: action)
		}

		static func track(_ action: @escaping () -> Void) -> Target {
			Target(id: "track", title: String(localized: "view-track"), nestedTitle: String(localized: "view-target-track"), systemImage: "info.circle", action: action)
		}
	}

	let targets: [Target]

	var body: some View {
		if self.targets.count > 1 {
			Menu {
				ForEach(self.targets) { target in
					Button {
						target.action()
					} label: {
						Label(target.nestedTitle, systemImage: target.systemImage)
					}
					.tint(Color.primary)
				}
			} label: {
				Label(String(localized: "view"), systemImage: "eye")
			}
			.tint(Color.primary)
		} else if let only = self.targets.first {
			Button {
				only.action()
			} label: {
				Label(only.title, systemImage: only.systemImage)
			}
			.tint(Color.primary)
		}
	}
}
