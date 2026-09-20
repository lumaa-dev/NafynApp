// Made by Lumaa

import SwiftUI
import Safyn

struct QueuePanel: View {
	var body: some View {
		List {
			ForEach(Array(PlayerEngine.shared.queue.enumerated()), id: \.element.id) { index, track in
				Button {
					PlayerEngine.shared.play(track, queue: PlayerEngine.shared.queue)
				} label: {
					HStack(spacing: 10) {
						CoverImage(url: track.highResCoverURL, cornerRadius: 6)
							.frame(width: 44, height: 44)

						VStack(alignment: .leading, spacing: 2) {
							Text(track.title)
								.font(DTFont.serif(18))
								.foregroundStyle(index == PlayerEngine.shared.currentIndex ? DTColor.accentStart : DTColor.textPrimary)
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
						PlayerEngine.shared.removeFromQueue(at: index)
					} label: {
						Label(String(localized: "remove"), systemImage: "trash")
					}
					.tint(DTColor.buttonDanger)
				}
			}
			.onMove(perform: PlayerEngine.shared.shuffleEnabled ? nil : { source, destination in
				PlayerEngine.shared.moveInQueue(from: source, to: destination)
			})
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.scrollEdgeEffectStyle(.soft, for: .all)
	}
}
