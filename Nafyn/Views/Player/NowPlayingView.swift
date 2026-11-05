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

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	@State private var activePanel: PanelTab? = nil
	@State private var sliderValue: Float = Float(PlaybackSource.currentTime)
	@State private var isDraggingSlider = false
	@State private var isPresentingAddToPlaylist = false

	/// Whether the window is wider than tall, measured on the container rather than the screen.
	@State private var isLandscape = false

	/// Whether the device is partly folded: a `division` reserved region (the fold) is active over this view.
	@State private var isFolded = false

	/// An iPhone held sideways: a window too short for the stacked cover-over-controls layout.
	private var isShortLandscape: Bool {
		!self.isFolded && self.verticalSizeClass == .compact
	}

	/// The artwork and controls sit beside (or, in a taller-than-wide window, stacked with) the queue/lyrics
	/// when the device is partly folded in either orientation, or when the window is regular in both
	/// directions and wider than tall (iPhone Duo inner display held sideways, iPad landscape). A fully open,
	/// upright inner display keeps the compact layout, where a panel replaces the artwork exactly as on any
	/// other iPhone; so does an iPhone held sideways, through its own ``landscapeLayout(_:)``.
	private var isWide: Bool {
		self.isFolded || (self.horizontalSizeClass == .regular && self.isLandscape && self.verticalSizeClass != .compact)
	}

	/// The panel currently on screen. A wide layout always has room for one, so it falls back to the queue.
	private var visiblePanel: PanelTab? {
		self.isWide ? (self.activePanel ?? .queue) : self.activePanel
	}

	var body: some View {
		// No navigation container on purpose: `ArrangementView` must not live inside one, and this screen
		// has no navigation of its own (it is a full-screen cover; links dismiss it and push on the tab).
		Group {
			if let track = PlaybackSource.track {
				if self.isWide {
					self.wideLayout(track)
				} else if self.isShortLandscape {
					self.landscapeLayout(track)
				} else {
					self.compactLayout(track)
				}
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
			if let track = PlaybackSource.track {
				CoverMeshBackground(coverURL: track.setCoverSize(500))
					.ignoresSafeArea()
			} else {
				DTColor.background.ignoresSafeArea()
			}
		}
		.onGeometryChange(for: Bool.self) { proxy in
			proxy.size.width > proxy.size.height
		} action: { newValue in
			self.isLandscape = newValue
		}
		.onGeometryChange(for: Bool.self) { proxy in
			if #available(iOS 27.1, *) {
				return !proxy.reservedRegions(kind: .division).isEmpty
			}
			return false
		} action: { newValue in
			self.isFolded = newValue
		}
		.navigationTransition(.zoom(sourceID: "miniPlayer", in: self.namespace))
		.sheet(isPresented: self.$isPresentingAddToPlaylist) {
			if let trackId = PlaybackSource.track?.id {
				AddToPlaylistSheet(mediaIds: [trackId])
			}
		}
	}

	@ViewBuilder
	private func compactLayout(_ track: MediaRow) -> some View {
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
		// an upright inner display is far wider than a phone: keep the phone-sized column, centered
		.frame(maxWidth: DTLayout.panelWidth)
		.frame(maxWidth: .infinity)
	}

	/// An iPhone held sideways. The portrait layout turned on its side: the cover (or, when one is open, the
	/// lyrics/queue panel in its place) on one side, title, actions, scrubber and transport on the other.
	@ViewBuilder
	private func landscapeLayout(_ track: MediaRow) -> some View {
		SplitPanes {
			Group {
				if let panel = self.activePanel {
					self.panelContent(panel)
				} else {
					CoverImage(url: track.setCoverSize(1000))
						.aspectRatio(1, contentMode: .fit)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		} secondary: {
			VStack(spacing: 0) {
				if let error = PlayerEngine.shared.lastError {
					Text(error)
						.font(DTFont.system(13))
						.foregroundStyle(DTColor.statusFailure)
						.padding(.bottom, 8)
				}

				self.titles(track)
					.frame(maxWidth: .infinity, alignment: .leading)

				Spacer(minLength: 8)

				self.actionRow(track)
					.padding(.vertical, 8)

				self.scrubber
				self.transportControls
					.padding(.top, 8)
			}
			.frame(maxWidth: 460)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
	}

	/// Cover, actions, scrubber and transport beside (or, in a window taller than wide, stacked with) the
	/// queue/lyrics. `ArrangementView` picks the side-by-side or stacked placement and respaces the two
	/// around the fold when an iPhone Duo is partly open. Side by side the controls lead; stacked the
	/// panel takes the upper half and the controls the lower, within thumb reach.
	@ViewBuilder
	private func wideLayout(_ track: MediaRow) -> some View {
		Group {
			if self.isLandscape {
				SplitPanes {
					self.controlsPane(track)
				} secondary: {
					self.panel
				}
			} else {
				SplitPanes {
					self.panel
				} secondary: {
					self.controlsPane(track)
				}
			}
		}
		.padding(.horizontal, 32)
		.padding(.top, 20)
		.padding(.bottom, 8)
	}

	private var panel: some View {
		self.panelContent(self.visiblePanel ?? .queue)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	@ViewBuilder
	private func controlsPane(_ track: MediaRow) -> some View {
		VStack(spacing: 0) {
			if let error = PlayerEngine.shared.lastError {
				Text(error)
					.font(DTFont.system(13))
					.foregroundStyle(DTColor.statusFailure)
					.padding(.bottom, 8)
			}

			// the cover is the flexible piece: it shrinks to whatever height the pane has left
			self.fullHeader(track)

			Spacer(minLength: 20)

			self.actionRow(track)
				.padding(.vertical, 14)

			self.scrubber
			self.transportControls
				.padding(.top, 18)
		}
		.frame(maxWidth: 460)
		.frame(maxWidth: .infinity)
	}

	/// The large-cover layout shown whenever neither the lyrics nor the queue panel is open. The cover
	/// fills the available width (a large square, not the old fixed 300pt box) with the title/artist
	/// left-aligned beneath it, matching the reference layout rather than the previous centered block —
	/// `CoverMeshBackground` behind it is untouched.
	@ViewBuilder
	private func fullHeader(_ track: MediaRow) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			CoverImage(url: track.setCoverSize(1000))
				.aspectRatio(1, contentMode: .fit)
				.frame(maxWidth: .infinity)

			self.titles(track)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	@ViewBuilder
	private func titles(_ track: MediaRow) -> some View {
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
	}

	/// "Playing on {device}" while this screen is only mirroring another device (Nafyn Unity slave).
	@ViewBuilder
	private var hostBadge: some View {
		if let host = PlaybackSource.hostLabel {
			Label {
				Text(String(format: String(localized: "unity-playing-on"), host))
			} icon: {
				Image(.nafynUnity)
			}
			.font(DTFont.system(13, weight: .medium))
			.foregroundStyle(DTColor.textPrimary.opacity(0.6))
			.padding(.top, 2)
		}
	}

	@ViewBuilder
	private func panelContent(_ panel: PanelTab) -> some View {
		switch panel {
			case .queue:
				QueuePanel()
			case .lyrics:
				if let trackId = PlaybackSource.track?.id {
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
			self.circleToggle(icon: "quote.bubble.fill", isActive: self.visiblePanel == .lyrics) {
				self.togglePanel(.lyrics)
			}

			self.pill(track)

			self.circleToggle(icon: "list.bullet", isActive: self.visiblePanel == .queue) {
				self.togglePanel(.queue)
			}
		}
	}

	/// Compact: a second tap on the open panel closes it. Wide: one panel is always showing, so a tap
	/// only ever switches to the other one.
	private func togglePanel(_ panel: PanelTab) {
		withAnimation(.easeInOut(duration: 0.25)) {
			if self.isWide {
				self.activePanel = panel
			} else {
				self.activePanel = self.activePanel == panel ? nil : panel
			}
		}
	}

	@ViewBuilder
	private func circleToggle(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: icon)
				.font(DTFont.system(15))
				.foregroundStyle(isActive ? DTColor.accentStart : DTColor.textPrimary.opacity(0.75))
				.frame(width: 36, height: 36)
				.background(Circle().fill(DTColor.surfaceSelect.opacity(isActive ? 1 : 0.55)))
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func pill(_ track: MediaRow) -> some View {
		Group {
			// the wide layout already shows title/artist beside the panel, so the pill stays on the actions
			if self.activePanel != nil && !self.isWide {
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
							.tint(Color.primary)
						}
						if let artistId = track.artistMbid {
							Button {
								Navigator.shared.send(to: .artist(id: artistId))
								PlayerEngine.shared.isExpanded = false
							} label: {
								Label("view-artist", systemImage: "person")
							}
							.tint(Color.primary)
						}
						Button {
							self.isPresentingAddToPlaylist = true
						} label: {
							Label("add-to-playlist", systemImage: "text.badge.plus")
						}
						.tint(Color.primary)
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
				range: 0...Float(max(PlaybackSource.duration, 1)),
				isDragging: self.$isDraggingSlider
			) {
				PlaybackSource.seek(to: TimeInterval(self.sliderValue))
			}
			.frame(height: 20)
			.onChange(of: PlaybackSource.currentTime) { _, newValue in
				guard !self.isDraggingSlider else { return }
				self.sliderValue = Float(newValue)
			}

			HStack {
				Text(Self.formatted(PlaybackSource.currentTime))
				Spacer()
				Text(Self.formatted(PlaybackSource.duration))
			}
			.font(DTFont.system(11))
			.foregroundStyle(DTColor.textPrimary.opacity(0.5))
		}
	}

	// MARK: - Transport

	@ViewBuilder
	private var transportControls: some View {
		HStack {
			// AirPlay routes this device's own audio, so it means nothing while mirroring another device
			Group {
				if PlaybackSource.isRemote {
					Image(.nafynUnity)
						.foregroundStyle(DTColor.textPrimary.opacity(0.6))
				} else {
					RoutePickerButton()
						.frame(width: 22, height: 22)
				}
			}
			.frame(maxWidth: .infinity)

			Button {
				PlaybackSource.prev()
			} label: {
				Image(systemName: "backward.fill")
					.font(DTFont.text(.title2))
					.foregroundStyle(DTColor.textPrimary)
			}
			.frame(maxWidth: .infinity)

			Button {
				PlaybackSource.togglePlay()
			} label: {
				Image(systemName: PlaybackSource.isPlaying ? "pause.fill" : "play.fill")
					.font(DTFont.system(38))
					.foregroundStyle(DTColor.textPrimary)
			}
			.keyboardShortcut(.space, modifiers: [])
			.frame(maxWidth: .infinity)

			Button {
				PlaybackSource.next()
			} label: {
				Image(systemName: "forward.fill")
					.font(DTFont.text(.title2))
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
		if PlaybackSource.isRemote {
			self.remoteRepeatButton
		} else {
			self.localShuffleRepeatButton
		}
	}

	/// Unity has no shuffle command, only repeat: tapping cycles the master's repeat mode.
	@ViewBuilder
	private var remoteRepeatButton: some View {
		let mode = RepeatMode(wireValue: UnityEngine.shared.remoteState?.repeatMode ?? "off")

		Image(systemName: mode == .track ? "repeat.1" : "repeat")
			.font(DTFont.text(.body))
			.foregroundStyle(mode == .off ? DTColor.textPrimary.opacity(0.6) : DTColor.accentStart)
			.frame(width: 44, height: 44)
			.contentShape(Rectangle())
			.onTapGesture {
				UnityEngine.shared.sendCommand(.cycleRepeat)
			}
			.sensoryFeedback(.selection, trigger: mode)
	}

	@ViewBuilder
	private var localShuffleRepeatButton: some View {
		let repeatMode = PlayerEngine.shared.repeatMode
		let showingRepeat = repeatMode != .off

		Image(systemName: showingRepeat ? (repeatMode == .track ? "repeat.1" : "repeat") : "shuffle")
			.font(DTFont.text(.body))
			.foregroundStyle(showingRepeat || PlayerEngine.shared.shuffleEnabled ? DTColor.accentStart : DTColor.textPrimary.opacity(0.6))
			.frame(width: 44, height: 44)
			.contentShape(Rectangle())
			.onTapGesture {
				PlayerEngine.shared.toggleShuffle()
			}
			.onLongPressGesture(minimumDuration: 0.25) {
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
