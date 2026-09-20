// Made by Lumaa

import SwiftUI
import Safyn

struct NowPlayingView: View {
	let namespace: Namespace.ID

	private enum PanelTab {
		case queue
		case lyrics
	}

	@State private var activePanel: PanelTab? = nil
	@State private var sliderValue: Float = Float(PlayerEngine.shared.currentTime)
	@State private var isDraggingSlider = false

	var body: some View {
		NavigationStack {
			Group {
				if let track = PlayerEngine.shared.currentTrack {
					VStack(spacing: 0) {
						if let error = PlayerEngine.shared.lastError {
							Text(error)
								.font(DTFont.system(13))
								.foregroundStyle(DTColor.statusFailure)
								.padding(.bottom, 8)
						}

						if self.activePanel == nil {
							self.fullHeader(track)

							Spacer(minLength: 20)

							self.scrubber
							self.transportControls
								.padding(.top, 16)
						} else {
							self.compactHeader(track)

							self.panelContent(self.activePanel!)
								.frame(maxHeight: .infinity)

							self.scrubber
							self.transportControls
								.padding(.vertical, 6)
						}

						self.toggleRow
							.padding(.top, self.activePanel == nil ? 28 : 10)
							.padding(.bottom, 8)
					}
					.padding(.horizontal)
					.padding(.top, self.activePanel == nil ? 20 : 12)
				} else {
					VStack {
						Spacer()
						Text("nothing-playing")
							.font(DTFont.system(18))
							.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						Spacer()
					}
				}
			}
			.background(DTColor.background.ignoresSafeArea())
		}
		.navigationTransition(.zoom(sourceID: "miniPlayer", in: self.namespace))
	}

	@ViewBuilder
	private func fullHeader(_ track: MediaRow) -> some View {
		VStack(spacing: 16) {
			CoverImage(url: track.highResCoverURL)
				.frame(width: 300, height: 300)

			VStack(spacing: 4) {
				Text(track.title)
					.font(DTFont.serif(24))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)
				Text(track.artistName)
					.font(DTFont.serif(16))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}
		}
	}

	@ViewBuilder
	private func compactHeader(_ track: MediaRow) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: track.highResCoverURL)
				.frame(width: 44, height: 44)

			VStack(alignment: .leading, spacing: 2) {
				Text(track.title)
					.font(DTFont.serif(16))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)
				Text(track.artistName)
					.font(DTFont.serif(13))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}

			Spacer()
		}
		.padding(.bottom, 12)
	}

	@ViewBuilder
	private func panelContent(_ panel: PanelTab) -> some View {
		switch panel {
			case .queue:
				QueuePanel()
			case .lyrics:
				if let trackId = PlayerEngine.shared.currentTrack?.id {
					LyricsPanel(trackId: trackId)
						.id(trackId)
				}
		}
	}

	@ViewBuilder
	private var scrubber: some View {
		VStack(spacing: 6) {
			PlayerSlider(
				self.$sliderValue,
				range: 0...Float(max(PlayerEngine.shared.duration, 1)),
				isDragging: self.$isDraggingSlider
			) {
				PlayerEngine.shared.seek(to: TimeInterval(self.sliderValue))
			}
			.frame(height: 20)
			.onChange(of: PlayerEngine.shared.currentTime) { _, newValue in
				guard !self.isDraggingSlider else { return }
				self.sliderValue = Float(newValue)
			}

			HStack {
				Text(Self.formatted(PlayerEngine.shared.currentTime))
				Spacer()
				Text(Self.formatted(PlayerEngine.shared.duration))
			}
			.font(DTFont.system(11))
			.foregroundStyle(DTColor.textPrimary.opacity(0.5))
		}
	}

	@ViewBuilder
	private var transportControls: some View {
		HStack {
			Button {
				PlayerEngine.shared.toggleShuffle()
			} label: {
				Image(systemName: "shuffle")
					.font(.body)
					.foregroundStyle(PlayerEngine.shared.shuffleEnabled ? DTColor.accentStart : DTColor.textPrimary.opacity(0.6))
			}
			.frame(maxWidth: .infinity)

			Button {
				PlayerEngine.shared.prev()
			} label: {
				Image(systemName: "backward.fill")
					.font(.title2)
					.foregroundStyle(DTColor.textPrimary)
			}
			.frame(maxWidth: .infinity)

			Button {
				PlayerEngine.shared.togglePlay()
			} label: {
				Image(systemName: PlayerEngine.shared.isPlaying ? "pause.circle.fill" : "play.circle.fill")
					.font(.system(size: 52))
					.foregroundStyle(DTColor.textPrimary)
			}
			.frame(maxWidth: .infinity)

			Button {
				PlayerEngine.shared.next()
			} label: {
				Image(systemName: "forward.fill")
					.font(.title2)
					.foregroundStyle(DTColor.textPrimary)
			}
			.frame(maxWidth: .infinity)

			Button {
				PlayerEngine.shared.repeatMode = PlayerEngine.shared.repeatMode.next
			} label: {
				Image(systemName: PlayerEngine.shared.repeatMode == .track ? "repeat.1" : "repeat")
					.font(.body)
					.foregroundStyle(PlayerEngine.shared.repeatMode == .off ? DTColor.textPrimary.opacity(0.6) : DTColor.accentStart)
			}
			.frame(maxWidth: .infinity)
		}
	}

	/// Toggleable queue/lyrics buttons, mirroring Apple Music's now-playing bottom row rather than the
	/// web app's segmented tab picker — tapping the active one collapses back to the full player.
	@ViewBuilder
	private var toggleRow: some View {
		HStack(spacing: 48) {
			Button {
				withAnimation(.easeInOut(duration: 0.25)) {
					self.activePanel = self.activePanel == .lyrics ? nil : .lyrics
				}
			} label: {
				Image(systemName: "quote.bubble")
					.font(.title3)
					.foregroundStyle(self.activePanel == .lyrics ? DTColor.accentStart : DTColor.textPrimary.opacity(0.6))
			}

			Button {
				withAnimation(.easeInOut(duration: 0.25)) {
					self.activePanel = self.activePanel == .queue ? nil : .queue
				}
			} label: {
				Image(systemName: "list.bullet")
					.font(.title3)
					.foregroundStyle(self.activePanel == .queue ? DTColor.accentStart : DTColor.textPrimary.opacity(0.6))
			}
		}
	}

	private static func formatted(_ time: TimeInterval) -> String {
		let total = Int(time.rounded())
		return String(format: "%d:%02d", total / 60, total % 60)
	}
}
