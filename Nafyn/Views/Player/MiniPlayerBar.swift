// Made by Lumaa

import SwiftUI
import Safyn

/// Docked bar, always present: shows the loaded track and a
/// "nothing playing" placeholder otherwise. Tapping the cover/title of a loaded track expands to
/// ``NowPlayingView``; the placeholder is inert. Transport controls sit alongside as sibling buttons so
/// they don't fight a wrapping `Button`'s gesture.
struct MiniPlayerBar: View {
	let namespace: Namespace.ID

	var body: some View {
		if PlaybackSource.track == nil {
			self.idle
		} else if let track = PlaybackSource.track {
			// Stays in place while the full player is open (it is covered anyway): the zoom needs its cover to
			// exist when the player opens, to grow out of it, and when the player closes, to shrink back into it.
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

				// another device is the one actually playing: this bar only mirrors and controls it
				if let host = PlaybackSource.hostLabel {
					Image(.nafynUnity)
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
						.accessibilityLabel(String(format: String(localized: "unity-playing-on"), host))
				}

//				Button {
//					PlayerEngine.shared.prev()
//				} label: {
//					Image(systemName: "backward.fill")
//				}

				Button {
					PlaybackSource.togglePlay()
				} label: {
					Image(systemName: PlaybackSource.isPlaying ? "pause.fill" : "play.fill")
						.frame(width: 20)
				}

				Button {
					PlaybackSource.next()
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
			// the same menu as a track row in the library, minus Play and Shuffle (it is playing already)
			.libraryItemMenu(item: .track(id: track.id), play: nil, share: ExternalShareItem(title: track.title, artist: track.artistName)) {
				// mirroring another device: it still has the track queued, so move it along
				if PlaybackSource.isRemote, PlaybackSource.track?.id == track.id {
					PlaybackSource.next()
				}
			}
			.padding(.horizontal)
		}
	}

	private var idle: some View {
		HStack(spacing: 12) {
			Image(systemName: "music.note")
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			Text("nothing-playing")
				.font(DTFont.serif(18))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				.lineLimit(1)

			Spacer()
		}
		.padding(.horizontal)
		.accessibilityElement(children: .combine)
	}

	private var progressFraction: CGFloat {
		guard PlaybackSource.duration > 0 else { return 0 }
		return CGFloat(PlaybackSource.currentTime / PlaybackSource.duration)
	}

	@ViewBuilder
	private func cover(_ track: MediaRow) -> some View {
		let image = CoverImage(url: track.listCoverURL)
			.frame(width: 44, height: 44)

		// the player grows out of the cover itself, clipped to the cover's own rounded shape from the first frame
		image.matchedTransitionSource(id: "miniPlayer", in: self.namespace) { source in
			source.clipShape(RoundedRectangle(cornerRadius: 10.0))
		}
	}
}
