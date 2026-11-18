// Made by Lumaa

import SwiftUI

/// A mix has no cover of its own: four of its tracks' covers in a grid, or the first one alone when there
/// are fewer (the web app's `MixCover`).
struct MixCover: View {
	let covers: [String]
	var size: UInt16 = 500
	var cornerRadius: CGFloat = 10

	var body: some View {
		let urls = self.covers.prefix(4).map { $0.contains("/art/") ? $0.coverArtURL(size: self.size / 2) : URL(string: $0) }
		Color.clear
			.aspectRatio(1.0, contentMode: .fit)
			.overlay {
				if urls.count >= 4 {
					Grid(horizontalSpacing: 0, verticalSpacing: 0) {
						GridRow {
							CoverImage(url: urls[0], cornerRadius: 0)
							CoverImage(url: urls[1], cornerRadius: 0)
						}
						GridRow {
							CoverImage(url: urls[2], cornerRadius: 0)
							CoverImage(url: urls[3], cornerRadius: 0)
						}
					}
				} else {
					CoverImage(url: urls.first ?? nil, cornerRadius: 0)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
			.accessibilityHidden(true)
	}
}
