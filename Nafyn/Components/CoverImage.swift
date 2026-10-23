// Made by Lumaa

import SwiftUI

/// The `AsyncImage` + placeholder pattern shared by `MusicCard` and every detail/player screen.
///
/// Cover Art Archive URLs are fetched through the server's cover cache (`CoverArtLoader`); every other URL
/// (uploaded covers, playlist images, avatars, artist photos) goes straight through `AsyncImage`.
struct CoverImage: View {
	var url: URL?
	var cornerRadius: CGFloat = 10.0

	/// The cover `loaded` was fetched for, so a stale image is never shown after `url` changes.
	@State private var loaded: (url: URL, image: UIImage)? = nil

	var body: some View {
		Group {
			if let url {
				if CoverArtLoader.shared.isConfigured, CoverArtReference(url: url) != nil {
					self.archived(url)
				} else {
					AsyncImage(url: url) { image in
						image
							.resizable()
							.aspectRatio(1.0, contentMode: .fill)
					} placeholder: {
						DTColor.surfaceSelect
					}
				}
			} else {
				DTColor.surfaceSelect
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
	}

	@ViewBuilder
	private func archived(_ url: URL) -> some View {
		// The synchronous cache hit keeps an already-loaded cover from flashing its placeholder.
		let image = CoverArtLoader.shared.cachedImage(for: url) ?? (self.loaded?.url == url ? self.loaded?.image : nil)

		Group {
			if let image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(1.0, contentMode: .fill)
			} else {
				DTColor.surfaceSelect
			}
		}
		.task(id: url) {
			guard CoverArtLoader.shared.cachedImage(for: url) == nil else { return }
			if let image = await CoverArtLoader.shared.image(for: url) {
				self.loaded = (url, image)
			}
		}
	}
}
