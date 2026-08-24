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
	var dimmed: Bool = false
	var verticalPadding: CGFloat = 6
	var onTap: (() -> Void)? = nil
	@ViewBuilder var trailing: () -> Trailing

	var body: some View {
		HStack(spacing: 12) {
			Button {
				self.onTap?()
			} label: {
				HStack(spacing: 12) {
					if let coverURL {
						CoverImage(url: coverURL)
							.frame(width: 44, height: 44)
					}

					if let index {
						Text(index)
							.font(DTFont.system(16))
							.foregroundStyle(DTColor.textPrimary.opacity(0.5))
							.frame(width: 24, alignment: .trailing)
					}

					VStack(alignment: .leading, spacing: 2) {
						Text(self.title)
							.font(DTFont.serif(19))
							.foregroundStyle(DTColor.textPrimary.opacity(self.dimmed ? 0.4 : 1.0))
							.lineLimit(1)

						if let subtitle {
							Text(subtitle)
								.font(DTFont.serif(16))
								.foregroundStyle(DTColor.textPrimary.opacity(0.5))
								.lineLimit(1)
						}
					}

					Spacer()

					Text(Self.formattedDuration(self.duration))
						.font(DTFont.system(12).monospacedDigit())
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
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
}

extension TrackRow where Trailing == EmptyView {
	init(coverURL: URL? = nil, index: String? = nil, title: String, subtitle: String? = nil, duration: TimeInterval, dimmed: Bool = false, verticalPadding: CGFloat = 6, onTap: (() -> Void)? = nil) {
		self.init(coverURL: coverURL, index: index, title: title, subtitle: subtitle, duration: duration, dimmed: dimmed, verticalPadding: verticalPadding, onTap: onTap, trailing: { EmptyView() })
	}
}
