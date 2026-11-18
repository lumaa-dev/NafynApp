// Made by Lumaa

import SwiftUI

/// A reusable "cover • number • title • subtitle • duration • trailing action" row shared by album,
/// playlist, and library track lists.
///
/// The tappable part (everything except `trailing`) is a real `Button` — `List` rows need one to
/// reliably register taps (a bare `.onTapGesture` is unreliable inside `List`). `trailing` is a
/// *sibling* of that button rather than nested inside its label, so an interactive trailing view (e.g.
/// a request/download button) isn't swallowed by the row button's hit-testing.
struct TrackRow<Trailing: View>: View {
	var coverURL: URL? = nil
	var index: String? = nil
	var title: String
	var subtitle: String? = nil
	var duration: TimeInterval
	var fileSize: Int64? = nil
	var dimmed: Bool = false
	var verticalPadding: CGFloat = 2
	var onTap: (() -> Void)? = nil
	@ViewBuilder var trailing: () -> Trailing

	@Environment(\.coverPalette) private var palette

	/// Tappable text: the cover palette's primary on cover-themed screens, the design-system color elsewhere.
	private var primaryText: Color { self.palette?.primary ?? DTColor.textPrimary }
	/// Non-tappable text.
	private var secondaryText: Color { self.palette?.secondary ?? DTColor.textPrimary.opacity(0.5) }

	var body: some View {
		HStack(spacing: 12) {
			Button {
				self.onTap?()
			} label: {
				HStack(spacing: 12) {
					if let coverURL {
						CoverImage(url: coverURL)
							.frame(width: 40, height: 40)
					}

					if let index {
						Text(index)
							.font(DTFont.system(16))
							.foregroundStyle(self.secondaryText)
							.frame(width: 24, alignment: .trailing)
					}

					VStack(alignment: .leading, spacing: 2) {
						Text(self.title)
							.font(DTFont.serif(19))
							// main information stays at full strength on cover-themed screens: an unreleased row is told apart by its countdown
							.foregroundStyle(self.primaryText.opacity(self.dimmed && self.palette == nil ? 0.4 : 1.0))
							.lineLimit(1)

						if let subtitle {
							Text(subtitle)
								.font(DTFont.serif(16))
								.foregroundStyle(self.secondaryText)
								.lineLimit(1)
						}
					}

					Spacer()

					VStack(alignment: .trailing, spacing: 2) {
						if DisplayPreferences.shared.showFileSize, let fileSize {
							Text(Self.formattedFileSize(fileSize))
								.font(DTFont.system(10).monospacedDigit())
								.foregroundStyle(self.secondaryText)
						}

						if DisplayPreferences.shared.showDuration {
							Text(Self.formattedDuration(self.duration))
								.font(DTFont.system(12).monospacedDigit())
								.foregroundStyle(self.secondaryText)
						}
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.disabled(self.onTap == nil)

			self.trailing()
		}
		.padding(.vertical, self.verticalPadding)
	}

	static func formattedDuration(_ duration: TimeInterval) -> String {
		let total = Int(duration.rounded())
		return String(format: "%d:%02d", total / 60, total % 60)
	}

	static func formattedFileSize(_ bytes: Int64) -> String {
		TrackRowFormatting.fileSizeFormatter.string(fromByteCount: bytes)
	}
}

/// Not nested in `TrackRow` — a generic type can't hold static stored properties.
private enum TrackRowFormatting {
	static let fileSizeFormatter: ByteCountFormatter = {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .file
		formatter.allowedUnits = [.useMB, .useKB, .useGB]
		return formatter
	}()
}

extension TrackRow where Trailing == EmptyView {
	init(coverURL: URL? = nil, index: String? = nil, title: String, subtitle: String? = nil, duration: TimeInterval, fileSize: Int64? = nil, dimmed: Bool = false, verticalPadding: CGFloat = 2, onTap: (() -> Void)? = nil) {
		self.init(coverURL: coverURL, index: index, title: title, subtitle: subtitle, duration: duration, fileSize: fileSize, dimmed: dimmed, verticalPadding: verticalPadding, onTap: onTap, trailing: { EmptyView() })
	}
}
