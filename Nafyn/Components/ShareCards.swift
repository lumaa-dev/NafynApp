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

/// Previews a share image and hands it to the share sheet (`ShareLink`, DESIGN.md "Sharing").
struct ShareImagePreview: View {
	let content: ShareCardContent

	@State private var image: Image?

	var body: some View {
		VStack(spacing: 20) {
			if let image {
				image
					.resizable()
					.aspectRatio(9 / 16, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 16))
					.padding(.horizontal, 40)

				ShareLink(item: image, preview: SharePreview(self.content.title, image: image)) {
					Label(String(localized: "share-image"), systemImage: "square.and.arrow.up")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())
				.padding(.horizontal)
			} else {
				ProgressView()
					.tint(DTColor.textPrimary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
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

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ShareImagePreview(content: self.content)
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

/// DESIGN.md "Lyrics Panel": tap-and-hold a paragraph opens this. Paragraphs are picked one by one, up to 210
/// characters in all (a paragraph that would go past it can't be added), and the card is shared as an image.
struct LyricsShareSheet: View {
	let lyrics: LyricsLayout
	let track: MediaRow?
	let initialParagraphId: String

	@Environment(\.dismiss) private var dismiss
	@State private var selected: [String] = []
	@State private var preview: ShareCardContent?

	private func text(of paragraph: LyricsLayout.Paragraph) -> [String] {
		paragraph.lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
	}

	private var selectedLines: [String] {
		self.lyrics.paragraphs.filter { self.selected.contains($0.id) }.flatMap { self.text(of: $0) }
	}

	private var characterCount: Int {
		self.selectedLines.joined(separator: "\n").count
	}

	private func fits(_ paragraph: LyricsLayout.Paragraph) -> Bool {
		let added = self.text(of: paragraph).joined(separator: "\n").count
		return self.characterCount + added + (self.selected.isEmpty ? 0 : 1) <= ShareCardContent.maxLyricsCharacters
	}

	var body: some View {
		NavigationStack {
			List {
				ForEach(self.lyrics.paragraphs.filter { !self.text(of: $0).isEmpty }, id: \.id) { paragraph in
					let isSelected = self.selected.contains(paragraph.id)
					Button {
						Haptics.selection()
						if isSelected {
							self.selected.removeAll { $0 == paragraph.id }
						} else {
							self.selected.append(paragraph.id)
						}
					} label: {
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
								.font(DTFont.system(22))
								.foregroundStyle(DTColor.textPrimary.opacity(isSelected ? 1 : 0.4))
							Text(self.text(of: paragraph).joined(separator: "\n"))
								.font(DTFont.serif(20))
								.foregroundStyle(DTColor.textPrimary)
								.multilineTextAlignment(.leading)
						}
					}
					.tint(Color.primary)
					.disabled(!isSelected && !self.fits(paragraph))
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
				// the paragraph that was held, when it fits on its own
				if self.selected.isEmpty, let paragraph = self.lyrics.paragraphs.first(where: { $0.id == self.initialParagraphId }), self.fits(paragraph) {
					self.selected = [paragraph.id]
				}
			}
		}
		.sheetBackground()
	}
}

extension ShareCardContent: Hashable, Identifiable {
	var id: Int { self.hashValue }
}
