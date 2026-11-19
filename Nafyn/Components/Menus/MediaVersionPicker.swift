// Made by Lumaa

import SwiftUI

/// Which version of an album or a track a detail screen shows: the MusicBrainz one ("catalog", requestable) or the
/// user's own copy ("library", playable).
enum MediaVersion: Hashable, CaseIterable {
	case catalog
	case library

	var title: String {
		switch self {
			case .catalog: String(localized: "version-catalog")
			case .library: String(localized: "version-library")
		}
	}

	var systemImage: String {
		switch self {
			case .catalog: "globe"
			case .library: "books.vertical"
		}
	}
}

/// The toolbar picker switching a detail screen between the catalog and the library version of the same album or
/// track, in place (``Navigator/replaceTop(where:with:)``). Only there when the other version exists.
///
/// Its label is text only, the version being shown, never a symbol (the choices inside carry theirs); like every
/// toolbar control its text and icons are the primary color, never the app's blue tint.
struct MediaVersionPicker: ToolbarContent {
	let current: MediaVersion
	/// The screen of the other version; `nil` leaves the picker out.
	let counterpart: Navigator.Paths?
	/// Which stack entry is this screen (it may have been opened as a recently played entry).
	let isCurrent: (Navigator.Paths) -> Bool

	var body: some ToolbarContent {
		if let counterpart = self.counterpart {
			ToolbarItem(placement: .principal) {
				Menu {
					Picker(selection: Binding(
						get: { self.current },
						set: { picked in
							guard picked != self.current else { return }
							PreviewPlayer.shared.stop()
							Navigator.shared.replaceTop(where: self.isCurrent, with: counterpart)
						}
					)) {
						ForEach(MediaVersion.allCases, id: \.self) { version in
							Label(version.title, systemImage: version.systemImage)
								.tag(version)
						}
					} label: {
						Text(String(localized: "version"))
					}
					.pickerStyle(.inline)
					.tint(Color.primary)
				} label: {
					Text(self.current.title)
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
				.accessibilityLabel(String(localized: "version"))
				.accessibilityValue(self.current.title)
			}
		}
	}
}

extension String {
	/// A MusicBrainz ID (a UUID): a catalog screen exists for it. Manual imports carry `manual-...` album IDs.
	var isMusicBrainzId: Bool {
		UUID(uuidString: self) != nil
	}
}
