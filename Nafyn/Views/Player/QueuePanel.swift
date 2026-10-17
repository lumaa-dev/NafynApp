// Made by Lumaa

import SwiftUI
import Safyn

struct QueuePanel: View {
	var body: some View {
		List {
			self.header
				.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)

			Section {
				ForEach(Array(PlaybackSource.queue.enumerated()), id: \.element.id) { index, track in
					Button {
						if PlaybackSource.isRemote {
							UnityEngine.shared.sendCommand(.playFromQueue(index: index))
						} else {
							PlayerEngine.shared.play(track, queue: PlayerEngine.shared.queue)
						}
					} label: {
						HStack(spacing: 10) {
							CoverImage(url: track.highResCoverURL, cornerRadius: 6)
								.frame(width: 44, height: 44)

							VStack(alignment: .leading, spacing: 2) {
								Text(track.title)
									.font(DTFont.serif(18))
									.foregroundStyle(index == PlaybackSource.currentIndex ? DTColor.accentStart : DTColor.textPrimary)
									.lineLimit(1)
								Text(track.artistName)
									.font(DTFont.serif(15))
									.foregroundStyle(DTColor.textPrimary.opacity(0.5))
									.lineLimit(1)
							}
							Spacer()
						}
					}
					.buttonStyle(.plain)
					.listRowBackground(Color.clear)
					.swipeActions {
						Button(role: .destructive) {
							if PlaybackSource.isRemote {
								UnityEngine.shared.sendCommand(.removeFromQueue(index: index))
							} else {
								PlayerEngine.shared.removeFromQueue(at: index)
							}
						} label: {
							Label(String(localized: "remove"), systemImage: "trash")
						}
						.tint(DTColor.buttonDanger)
					}
				}
				// Unity has no reorder command, so the remote queue is not movable
				.onMove(perform: PlaybackSource.isRemote || PlayerEngine.shared.shuffleEnabled ? nil : { source, destination in
					PlayerEngine.shared.moveInQueue(from: source, to: destination)
				})
			} header: {
				Text("playing-next")
					.font(DTFont.system(12, weight: .semibold))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					.textCase(.uppercase)
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
	}

	/// "Playing from {source}" — the source is approximated from the currently-playing track's own
	/// metadata (album, falling back to artist) rather than the original playlist/album name, since
	/// `PlayerEngine` only retains that source's ID for play-event reporting, not a display name.
	@ViewBuilder
	private var header: some View {
		if let track = PlaybackSource.track {
			HStack(spacing: 10) {
				RoundedRectangle(cornerRadius: 8, style: .continuous)
					.fill(DTColor.surfaceSelect)
					.frame(width: 36, height: 36)
					.overlay {
						Image(systemName: "music.note")
							.font(.system(size: 14))
							.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					}

				VStack(alignment: .leading, spacing: 1) {
					Text("playing-from")
						.font(DTFont.system(11, weight: .semibold))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						.textCase(.uppercase)
					Text(track.album ?? track.artistName)
						.font(DTFont.serif(17))
						.foregroundStyle(DTColor.textPrimary)
						.lineLimit(1)
				}

				Spacer()

				SixBandWaveform(tint: DTColor.textPrimary.opacity(0.7))
			}
		}
	}
}
