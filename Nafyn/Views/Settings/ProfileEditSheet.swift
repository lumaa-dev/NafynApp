// Made by Lumaa

import SwiftUI
import Safyn

/// Edits the signed-in user's own profile (avatar, display name, Last.fm, Discogs): ``ProfileSettingsSection`` in a
/// sheet. Closes once the fields are saved.
struct ProfileEditSheet: View {
	@Environment(\.dismiss) private var dismiss

	/// Replaced by what the server returns after every upload or save, so the avatar shown here follows.
	@State private var user: NafynUser
	let onUpdated: (NafynUser) -> Void

	init(user: NafynUser, onUpdated: @escaping (NafynUser) -> Void) {
		self._user = State(initialValue: user)
		self.onUpdated = onUpdated
	}

	var body: some View {
		NavigationStack {
			Form {
				ProfileSettingsSection(user: self.user, onSaved: { self.dismiss() }) { updated in
					self.user = updated
					self.onUpdated(updated)
				}
				.sheetRows()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.contentColumn(maxWidth: DTLayout.panelWidth)
			.navigationTitle(String(localized: "profile"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "close"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
		}
		.sheetBackground()
	}
}
