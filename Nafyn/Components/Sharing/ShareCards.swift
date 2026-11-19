// Made by Lumaa

import SwiftUI
import Safyn

/// What a share image shows: a track or an album (catalog screens), optionally with lyrics.
struct ShareCardContent {
	let title: String
	let subtitle: String?
	let coverURL: URL?
	/// Lyric lines, for "Share Lyrics" (at most ``ShareCardContent/maxLyricsCharacters`` in all).
	var lyrics: [String] = []

	/// DESIGN.md / TODO: a lyrics card holds at most 210 characters.
	static let maxLyricsCharacters = 210
}

/// The 9:16 image (DESIGN.md "Sharing": Instagram / Snapchat stories), rendered off-screen through `ImageRenderer`:
/// the cover must already be decoded (`cover`), an `AsyncImage` would come out blank. White text on the cover,
/// blurred and darkened enough to stay legible whatever its colours.
struct ShareCardView: View {
	let content: ShareCardContent
	let cover: UIImage?

	static let size = CGSize(width: 360, height: 640)

	var body: some View {
		ZStack {
			Group {
				if let cover {
					Image(uiImage: cover)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.blur(radius: 40)
						.scaleEffect(1.3)
				} else {
					DTColor.background
				}
			}
			.frame(width: Self.size.width, height: Self.size.height)
			.clipped()
			.overlay(Color.black.opacity(0.55))

			VStack(alignment: .leading, spacing: 18) {
				Spacer(minLength: 0)

				if let cover {
					Image(uiImage: cover)
						.resizable()
						.aspectRatio(1, contentMode: .fill)
						.frame(width: self.content.lyrics.isEmpty ? 260 : 96, height: self.content.lyrics.isEmpty ? 260 : 96)
						.clipShape(RoundedRectangle(cornerRadius: self.content.lyrics.isEmpty ? 18 : 10))
						.frame(maxWidth: .infinity, alignment: self.content.lyrics.isEmpty ? .center : .leading)
				}

				VStack(alignment: .leading, spacing: 4) {
					Text(self.content.title)
						.font(DTFont.serif(self.content.lyrics.isEmpty ? 34 : 24))
						.lineLimit(2)
					if let subtitle = self.content.subtitle {
						Text(subtitle)
							.font(DTFont.serifItalic(self.content.lyrics.isEmpty ? 22 : 18))
							.opacity(0.85)
							.lineLimit(1)
					}
				}

				if !self.content.lyrics.isEmpty {
					Text(self.content.lyrics.joined(separator: "\n"))
						.font(DTFont.serif(28).bold())
						.lineSpacing(4)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.top, 8)
				}

				Spacer(minLength: 0)

				Text(String("Nafyn"))
					.font(DTFont.serifItalic(18))
					.frame(maxWidth: .infinity, alignment: .center)
			}
			.foregroundStyle(.white)
			.padding(32)
			.frame(width: Self.size.width, height: Self.size.height)
		}
		.frame(width: Self.size.width, height: Self.size.height)
		.environment(\.colorScheme, .dark)
	}

	/// The card as an image, at 3x (1080 x 1920).
	@MainActor
	static func render(_ content: ShareCardContent) async -> Image? {
		var cover: UIImage?
		if let url = content.coverURL, let data = await CoverArtLoader.shared.contents(of: url) {
			cover = UIImage(data: data)
		}
		let renderer = ImageRenderer(content: ShareCardView(content: content, cover: cover))
		renderer.scale = 3
		return renderer.uiImage.map { Image(uiImage: $0) }
	}
}

/// Previews a share image and hands it to the share sheet (`ShareLink`, DESIGN.md "Sharing"). With a `link`, the
/// item's page on this Nafyn server can be shared from here too.
struct ShareImagePreview: View {
	let content: ShareCardContent
	var link: URL? = nil

	@State private var image: Image?

	var body: some View {
		VStack(spacing: 20) {
			if let image {
				image
					.resizable()
					.aspectRatio(9 / 16, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 16))
					.padding(.horizontal, 40)
			} else {
				ProgressView()
					.tint(DTColor.textPrimary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}

			VStack(spacing: 12) {
				if let link {
					ShareLink(item: link, subject: Text(self.content.title)) {
						Label(String(localized: "share-link"), systemImage: "link")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.filled())
				}

				if let image {
					let shareImage = ShareLink(item: image, preview: SharePreview(self.content.title, image: image)) {
						Label(String(localized: "share-image"), systemImage: "photo")
							.frame(maxWidth: .infinity)
					}
					if self.link == nil {
						shareImage.buttonStyle(.filled())
					} else {
						shareImage.buttonStyle(.hollow())
					}
				}
			}
			.padding(.horizontal)
		}
		.padding(.vertical)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(DTColor.background.ignoresSafeArea())
		.navigationTitle(String(localized: "share"))
		.navigationBarTitleDisplayMode(.inline)
		.task { self.image = await ShareCardView.render(self.content) }
	}
}

/// ``ShareImagePreview`` in its own sheet, with a Close button.
struct ShareImageSheet: View {
	let content: ShareCardContent
	var link: URL? = nil

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ShareImagePreview(content: self.content, link: self.link)
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

/// The sheet behind "Share" on a catalog track or album, and on a library one (which shares its catalog page, never
/// its library entry): the link of the page on this Nafyn server and the 9:16 image. A `ShareLink` in a menu (a
/// toolbar's overflow menu, a long-press) never presented its share sheet, so the menu only opens this and the
/// `ShareLink`s live here, where they work.
struct ShareCatalogSheet: View {
	@Environment(\.server) private var server: NafynServer?

	/// The item's page on the server: `t/<recording id>` or `a/<album id>`.
	let path: String
	let title: String
	let subtitle: String?
	let coverURL: URL?

	var body: some View {
		ShareImageSheet(
			content: ShareCardContent(title: self.title, subtitle: self.subtitle, coverURL: self.coverURL),
			link: self.server?.instance.baseURL.appending(path: self.path)
		)
	}
}

/// DESIGN.md "Lyrics Panel": tap-and-hold a lyric line opens this. Lines are picked one by one, up to 210
/// characters in all (a line that would go past it can't be added), and the card is shared as an image.
struct LyricsShareSheet: View {
	let lyrics: LyricsLayout
	let track: MediaRow?
	let initialLineId: String

	@Environment(\.dismiss) private var dismiss
	@State private var selected: [String] = []
	@State private var preview: ShareCardContent?

	/// Every line with something to show, in the song's order.
	private var lines: [LyricsLayout.Line] {
		self.lyrics.paragraphs.flatMap(\.lines).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
	}

	private var selectedLines: [String] {
		self.lines.filter { self.selected.contains($0.id) }.map(\.text)
	}

	private var characterCount: Int {
		self.selectedLines.joined(separator: "\n").count
	}

	private func fits(_ line: LyricsLayout.Line) -> Bool {
		self.characterCount + line.text.count + (self.selected.isEmpty ? 0 : 1) <= ShareCardContent.maxLyricsCharacters
	}

	var body: some View {
		NavigationStack {
			List {
				ForEach(self.lines, id: \.id) { line in
					let isSelected = self.selected.contains(line.id)
					Button {
						Haptics.selection()
						if isSelected {
							self.selected.removeAll { $0 == line.id }
						} else {
							self.selected.append(line.id)
						}
					} label: {
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
								.font(DTFont.system(22))
								.foregroundStyle(DTColor.textPrimary.opacity(isSelected ? 1 : 0.4))
							Text(line.text)
								.font(DTFont.serif(20))
								.foregroundStyle(DTColor.textPrimary)
								.multilineTextAlignment(.leading)
						}
					}
					.tint(Color.primary)
					.disabled(!isSelected && !self.fits(line))
					.accessibilityAddTraits(isSelected ? .isSelected : [])
					.listRowBackground(Color.clear)
				}
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.background(DTColor.background.ignoresSafeArea())
			.safeAreaInset(edge: .bottom) {
				Text("lyrics-share-count \(self.characterCount) \(ShareCardContent.maxLyricsCharacters)")
					.font(DTFont.system(14).monospacedDigit())
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.padding(8)
			}
			.navigationTitle(String(localized: "share-lyrics"))
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
				ToolbarItem(placement: .confirmationAction) {
					Button {
						self.preview = ShareCardContent(
							title: self.track?.title ?? "",
							subtitle: self.track?.artistName,
							coverURL: self.track?.setCoverSize(500),
							lyrics: self.selectedLines
						)
					} label: {
						Label(String(localized: "next"), systemImage: "arrow.right")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
					.disabled(self.selected.isEmpty)
				}
			}
			.navigationDestination(item: self.$preview) { content in
				ShareImagePreview(content: content)
			}
			.onAppear {
				// the line that was held, when it fits on its own
				if self.selected.isEmpty, let line = self.lines.first(where: { $0.id == self.initialLineId }), self.fits(line) {
					self.selected = [line.id]
				}
			}
		}
		.sheetBackground()
	}
}

extension ShareCardContent: Hashable, Identifiable {
	var id: Int { self.hashValue }
}
