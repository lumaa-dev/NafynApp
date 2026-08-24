// Made by Lumaa

import SwiftUI

/// The `AsyncImage` + placeholder pattern shared by `MusicCard` and every detail/player screen.
struct CoverImage: View {
	var url: URL?
	var cornerRadius: CGFloat = 10.0

	var body: some View {
		Group {
			if let url {
				AsyncImage(url: url) { image in
					image
						.resizable()
						.aspectRatio(1.0, contentMode: .fill)
				} placeholder: {
					DTColor.surfaceSelect
				}
			} else {
				DTColor.surfaceSelect
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
	}
}
