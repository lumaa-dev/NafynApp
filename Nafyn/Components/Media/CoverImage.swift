// Made by Lumaa

import SwiftUI

/// A zero radius means edge to edge: no clip at all, so `backgroundExtensionEffect()` sees the raw image.
private struct CornerClip: ViewModifier {
	var radius: CGFloat

	@ViewBuilder
	func body(content: Content) -> some View {
		if self.radius > 0 {
			content.clipShape(RoundedRectangle(cornerRadius: self.radius))
		} else {
			content
		}
	}
}

/// The `AsyncImage` + placeholder pattern shared by `MusicCard` and every detail/player screen.
///
/// Server cover paths (`/api/v1/art/...`, relative) are fetched through `CoverArtLoader`, which prepends the
/// session's server URL and sends its auth; every other URL (uploaded covers, playlist images, avatars,
/// artist photos) goes straight through `AsyncImage`.
struct CoverImage: View {
	var url: URL?
	var cornerRadius: CGFloat = 10.0

	/// Shown while the cover loads, or when there is none.
	var placeholder: Color = DTColor.surfaceSelect

	/// The cover `loaded` was fetched for, so a stale image is never shown after `url` changes.
	@State private var loaded: (url: URL, image: UIImage)? = nil

	/// A skeleton (`redacted(reason: .placeholder)`, DESIGN.md "Skeleton loading") draws the cover's shape only and
	/// loads nothing.
	@Environment(\.redactionReasons) private var redactionReasons

	var body: some View {
		Group {
			if self.redactionReasons.contains(.placeholder) {
				DTColor.surfaceSelect
			} else if let url {
				if CoverArtLoader.shared.isConfigured, CoverArtReference(url: url) != nil {
					self.served(url)
				} else {
					AsyncImage(url: url) { image in
						image
							.resizable()
							.aspectRatio(1.0, contentMode: .fill)
					} placeholder: {
						self.placeholder
					}
				}
			} else {
				self.placeholder
			}
		}
		.modifier(CornerClip(radius: self.cornerRadius))
	}

	@ViewBuilder
	private func served(_ url: URL) -> some View {
		// The synchronous cache hit keeps an already-loaded cover from flashing its placeholder.
		let image = CoverArtLoader.shared.cachedImage(for: url) ?? (self.loaded?.url == url ? self.loaded?.image : nil)

		Group {
			if let image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(1.0, contentMode: .fill)
			} else {
				self.placeholder
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
