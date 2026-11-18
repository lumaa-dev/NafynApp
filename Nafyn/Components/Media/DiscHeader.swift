// Made by Lumaa

import SwiftUI

/// Header above one disc's tracks on a multi-disc album. Only shown when the album spans several discs.
struct DiscHeader: View {
	var number: Double
	var title: String?
	var isFirst: Bool
	var palette: CoverPalette

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "opticaldisc")
			Text(self.title ?? String(localized: "disc-number \(Int(self.number))"))
		}
		.font(DTFont.system(15, weight: .semibold))
		.foregroundStyle(self.palette.secondary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.top, self.isFirst ? 0 : 20)
		.padding(.bottom, 4)
	}
}
