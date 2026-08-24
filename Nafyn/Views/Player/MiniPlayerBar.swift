// Made by Lumaa

import SwiftUI
import Safyn

/// Docked bar shown whenever a track is loaded, except while the full player is open. Tapping the
/// cover/title expands to ``NowPlayingView``; transport controls sit alongside as sibling buttons so
/// they don't fight a wrapping `Button`'s gesture.
struct MiniPlayerBar: View {
	@Environment(\.zoomNamespace) private var zoomNamespace: Namespace.ID?

	var body: some View {
		if let track = PlayerEngine.shared.currentTrack, !PlayerEngine.shared.isExpanded {
			HStack(spacing: 12) {
				self.cover(track)

				VStack(alignment: .leading, spacing: 2) {
					Text(track.title)
						.font(DTFont.serif(18))
						.foregroundStyle(DTColor.textPrimary)
						.lineLimit(1)
					Text(track.artistName)
						.font(DTFont.serif(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
						.lineLimit(1)
				}

				Spacer()

//				Button {
//					PlayerEngine.shared.prev()
//				} label: {
//					Image(systemName: "backward.fill")
//				}

				Button {
					PlayerEngine.shared.togglePlay()
				} label: {
					Image(systemName: PlayerEngine.shared.isPlaying ? "pause.fill" : "play.fill")
						.frame(width: 20)
				}

				Button {
					PlayerEngine.shared.next()
				} label: {
					Image(systemName: "forward.fill")
				}
			}
			.foregroundStyle(DTColor.textPrimary)
			.buttonStyle(.plain)
			.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.contentShape(Rectangle())
			.onTapGesture {
				PlayerEngine.shared.isExpanded = true
			}
			.padding(.horizontal)
		}
	}

	private var progressFraction: CGFloat {
		guard PlayerEngine.shared.duration > 0 else { return 0 }
		return CGFloat(PlayerEngine.shared.currentTime / PlayerEngine.shared.duration)
	}

	@ViewBuilder
	private func cover(_ track: MediaRow) -> some View {
		let image = CoverImage(url: track.coverArt.flatMap { URL(string: $0) })
			.frame(width: 44, height: 44)

		if let zoomNamespace {
			image.matchedTransitionSource(id: "miniPlayer", in: zoomNamespace)
		} else {
			image
		}
	}
}
