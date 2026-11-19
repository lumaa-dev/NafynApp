// Made by Lumaa

import SwiftUI

/// An artist's logo (TheAudioDB: a transparent, horizontal PNG, 800 x 310) in place of their name.
///
/// DESIGN.md has no section for it; it follows "Contrast": a logo is the artist's name drawn, so like any text it is
/// white (or black) against what is behind it - drawn as a template in the text color, never in its own colors,
/// which are often black on transparent and would vanish on Nafyn's background. The name is its accessibility
/// label, and is shown instead while the logo loads or when it cannot be loaded.
struct ArtistLogo: View {
	let url: URL
	let name: String

	/// The logo's own proportions (800 x 310).
	private static let aspectRatio: CGFloat = 800 / 310
	@ScaledMetric(relativeTo: .largeTitle) private var maxWidth: CGFloat = 260

	var body: some View {
		AsyncImage(url: self.url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
			switch phase {
				case .success(let image):
					image
						.resizable()
						.renderingMode(.template)
						.aspectRatio(Self.aspectRatio, contentMode: .fit)
						.foregroundStyle(DTColor.textPrimary)
						.transition(.opacity)
				default:
					self.nameText
			}
		}
		// as tall as the logo will be, so the screen doesn't jump when it arrives
		.frame(maxWidth: self.maxWidth)
		.frame(height: self.maxWidth / Self.aspectRatio)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(self.name)
		.accessibilityAddTraits(.isHeader)
	}

	private var nameText: some View {
		Text(self.name)
			.font(DTFont.serif(31))
			.foregroundStyle(DTColor.textPrimary)
			.multilineTextAlignment(.center)
			.minimumScaleFactor(0.6)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
