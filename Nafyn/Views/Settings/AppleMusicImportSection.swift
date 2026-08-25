// Made by Lumaa

import SwiftUI

struct AppleMusicImportSection: View {
	@State private var showingImport = false

	var body: some View {
		Section {
			Button {
				self.showingImport = true
			} label: {
				Label(String(localized: "import-apple-music"), systemImage: "applelogo")
					.foregroundStyle(Color.primary)
			}
			.tint(Color.primary)
		}
		header: {
			Text(String(localized: "import"))
		} footer: {
			Text(String(localized: "import-apple-music-footer"))
		}
		.sheet(isPresented: self.$showingImport) {
			AppleMusicImportSheet()
		}
	}
}
