// Made by Lumaa

import SwiftUI
import UIKit

/// The profile toolbar button's icon: the user's picture, or a person symbol while they have none (or it is
/// still loading).
///
/// The picture is cut into a circle of the icon's size ahead of time and handed over as a plain image (tagged as not-a-template): a toolbar
/// button sizes itself from its content and ignores a SwiftUI `clipShape`, so a live `AsyncImage` came out square and
/// stretched the button.
struct ProfileAvatarLabel: View {
	var url: URL?

	@State private var picture: UIImage? = nil

	var body: some View {
		Label {
			Text("profile")
		} icon: {
			if let picture {
				Image(uiImage: picture)
					.renderingMode(.original)
			} else {
				Image(systemName: "person.crop.circle")
			}
		}
		.labelStyle(.iconOnly)
		.task(id: self.url) {
			guard let url else {
				self.picture = nil
				return
			}
			if let cached = Self.cache.object(forKey: url as NSURL) {
				self.picture = cached
				return
			}
			let scale = UITraitCollection.current.displayScale
			let circle = await Task.detached(priority: .userInitiated) { () -> UIImage? in
				guard let data = try? await URLSession.shared.data(from: url).0, let image = UIImage(data: data) else { return nil }
				return Self.circle(from: image, side: Self.side, scale: scale)
			}.value
			guard let circle else { return }
			Self.cache.setObject(circle, forKey: url as NSURL)
			self.picture = circle
		}
	}

	private static let side: CGFloat = 32
	private static let cache = NSCache<NSURL, UIImage>()

	/// `image` cropped to the centered square, scaled to `side` points and clipped to a circle.
	private static func circle(from image: UIImage, side: CGFloat, scale: CGFloat) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.scale = scale
		format.opaque = false
		let rect = CGRect(x: 0, y: 0, width: side, height: side)

		let rendered = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
			UIBezierPath(ovalIn: rect).addClip()

			// aspect fill
			let ratio = max(side / image.size.width, side / image.size.height)
			let drawn = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
			image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
		}

		// set on the image itself: the toolbar turns the button's image into a bar item image and drops SwiftUI's
		// `.renderingMode(.original)`, then tints the picture like a symbol (every pixel the button's white)
		return rendered.withRenderingMode(.alwaysOriginal)
	}
}
