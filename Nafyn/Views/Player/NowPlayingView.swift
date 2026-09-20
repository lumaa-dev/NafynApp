// Made by Lumaa

import SwiftUI
import AVKit
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
	@State private var isPresentingAddToPlaylist = false

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
						} else {
							Spacer(minLength: 4)
							self.panelContent(self.activePanel!)
								.frame(maxHeight: .infinity)
						}

						self.actionRow(track)
							.padding(.vertical, 14)

						self.scrubber
						self.transportControls
							.padding(.top, 18)
					}
					.padding(.horizontal)
					.padding(.top, self.activePanel == nil ? 20 : 12)
					.padding(.bottom, 8)
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
			.background {
				if let track = PlayerEngine.shared.currentTrack {
					CoverMeshBackground(coverURL: track.highResCoverURL)
						.ignoresSafeArea()
				} else {
					DTColor.background.ignoresSafeArea()
				}
			}
		}
		.navigationTransition(.zoom(sourceID: "miniPlayer", in: self.namespace))
		.sheet(isPresented: self.$isPresentingAddToPlaylist) {
			if let trackId = PlayerEngine.shared.currentTrack?.id {
				AddToPlaylistSheet(mediaIds: [trackId])
			}
		}
	}

	/// The large-cover layout shown whenever neither the lyrics nor the queue panel is open. The cover
	/// fills the available width (a large square, not the old fixed 300pt box) with the title/artist
	/// left-aligned beneath it, matching the reference layout rather than the previous centered block —
	/// `CoverMeshBackground` behind it is untouched.
	@ViewBuilder
	private func fullHeader(_ track: MediaRow) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			CoverImage(url: track.highResCoverURL)
				.aspectRatio(1, contentMode: .fit)
				.frame(maxWidth: .infinity)

			VStack(alignment: .leading, spacing: 4) {
				Text(track.title)
					.font(DTFont.serif(26))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)
				Text(track.artistName)
					.font(DTFont.serif(17))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
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

	// MARK: - Action row

	/// Lyrics toggle · contextual pill · queue toggle, mirroring the reference's row directly below the
	/// header/panel rather than the previous bottom-of-screen toggle row. The pill itself is contextual:
	/// track actions (add to playlist, more) when the full header is showing, or a tappable
	/// "title • artist" label that collapses back to it when a panel is open.
	@ViewBuilder
	private func actionRow(_ track: MediaRow) -> some View {
		HStack(spacing: 10) {
			self.circleToggle(icon: "quote.bubble.fill", isActive: self.activePanel == .lyrics) {
				withAnimation(.easeInOut(duration: 0.25)) {
					self.activePanel = self.activePanel == .lyrics ? nil : .lyrics
				}
			}

			self.pill(track)

			self.circleToggle(icon: "list.bullet", isActive: self.activePanel == .queue) {
				withAnimation(.easeInOut(duration: 0.25)) {
					self.activePanel = self.activePanel == .queue ? nil : .queue
				}
			}
		}
	}

	@ViewBuilder
	private func circleToggle(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(.system(size: 15))
				.foregroundStyle(isActive ? DTColor.accentStart : DTColor.textPrimary.opacity(0.75))
				.frame(width: 36, height: 36)
				.background(Circle().fill(DTColor.surfaceSelect.opacity(isActive ? 1 : 0.55)))
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func pill(_ track: MediaRow) -> some View {
		Group {
			if self.activePanel != nil {
				Button {
					withAnimation(.easeInOut(duration: 0.25)) {
						self.activePanel = nil
					}
				} label: {
					Text("\(track.title) • \(track.artistName)")
						.font(DTFont.system(14, weight: .medium))
						.lineLimit(1)
				}
				.buttonStyle(.plain)
				.foregroundStyle(DTColor.textPrimary)
			} else {
				HStack(spacing: 32) {
					Button {
						self.isPresentingAddToPlaylist = true
					} label: {
						Image(systemName: "text.badge.plus")
					}

					Menu {
						if !track.albumId.isEmpty {
							Button {
								Navigator.shared.send(to: .album(id: track.albumId))
								PlayerEngine.shared.isExpanded = false
							} label: {
								Label("view-album", systemImage: "square.stack")
							}
						}
						if let artistId = track.artistMbid {
							Button {
								Navigator.shared.send(to: .artist(id: artistId))
								PlayerEngine.shared.isExpanded = false
							} label: {
								Label("view-artist", systemImage: "person")
							}
						}
						Button {
							self.isPresentingAddToPlaylist = true
						} label: {
							Label("add-to-playlist", systemImage: "text.badge.plus")
						}
					} label: {
						Image(systemName: "ellipsis")
					}
					.tint(Color.primary)
				}
				.foregroundStyle(DTColor.textPrimary.opacity(0.85))
			}
		}
		.padding(.all, 8)
		.background(Capsule().fill(DTColor.surfaceSelect.opacity(0.55)))
		.frame(maxWidth: .infinity)
	}

	// MARK: - Scrubber

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

	// MARK: - Transport

	@ViewBuilder
	private var transportControls: some View {
		HStack {
			RoutePickerButton()
				.frame(width: 22, height: 22)
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
				Image(systemName: PlayerEngine.shared.isPlaying ? "pause.fill" : "play.fill")
					.font(.system(size: 38))
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

			self.shuffleRepeatButton
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.plain)
	}

	/// A single glyph doing shuffle's job on tap and repeat's on long-press, mirroring Apple Music's own
	/// now-playing row (which only has room for one icon in this slot): tapping always toggles shuffle;
	/// holding cycles `repeatMode`, taking over the glyph — and the accent tint — while active.
	@ViewBuilder
	private var shuffleRepeatButton: some View {
		let repeatMode = PlayerEngine.shared.repeatMode
		let showingRepeat = repeatMode != .off

		Image(systemName: showingRepeat ? (repeatMode == .track ? "repeat.1" : "repeat") : "shuffle")
			.font(.body)
			.foregroundStyle(showingRepeat || PlayerEngine.shared.shuffleEnabled ? DTColor.accentStart : DTColor.textPrimary.opacity(0.6))
			.frame(width: 44, height: 44)
			.contentShape(Rectangle())
			.onTapGesture {
				PlayerEngine.shared.toggleShuffle()
			}
			.onLongPressGesture(minimumDuration: 0.45) {
				PlayerEngine.shared.repeatMode = PlayerEngine.shared.repeatMode.next
			}
			.sensoryFeedback(.selection, trigger: repeatMode)
	}

	private static func formatted(_ time: TimeInterval) -> String {
		let total = Int(time.rounded())
		return String(format: "%d:%02d", total / 60, total % 60)
	}
}

/// Native AirPlay/Bluetooth route picker — a real, functioning route switcher (not a decorative glyph),
/// wrapping the system's own `AVRoutePickerView` since SwiftUI has no first-party equivalent.
private struct RoutePickerButton: UIViewRepresentable {
	func makeUIView(context: Context) -> AVRoutePickerView {
		let view = AVRoutePickerView()
		view.backgroundColor = .clear
		view.prioritizesVideoDevices = false
		return view
	}

	func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
		uiView.tintColor = UIColor(DTColor.textPrimary)
		uiView.activeTintColor = UIColor(DTColor.accentStart)
	}
}
