// Made by Lumaa

import SwiftUI
import AVFoundation
import Safyn

/// The in-app story player for a year's highlight reel, from `Insights.reel(year:)`.
///
/// Slides advance on their own (each track slide runs for its audio excerpt's length), and tapping the
/// left/right half steps back/forward. The reel plays its own audio, so the main `PlayerEngine` is
/// paused for the duration and never mixed with it.
struct HighlightReelView: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	let year: Int

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Insights.reel(year: self.year)) as HighlightReel
		} skeleton: {
			AnyView(
				ZStack {
					DTColor.background.ignoresSafeArea()
					ProgressView()
						.tint(DTColor.textPrimary)
				}
			)
		} content: { reel, reload in
			HighlightReelPlayer(reel: reel, reload: reload)
		}
		.overlay(alignment: .topTrailing) {
			Button {
				self.dismiss()
			} label: {
				Image(systemName: "xmark")
					.font(DTFont.system(16, weight: .semibold))
					.padding(10)
					.background(.ultraThinMaterial, in: Circle())
			}
			.tint(Color.primary)
			.padding()
		}
	}
}

private struct HighlightReelPlayer: View {
	@Environment(\.server) private var server: NafynServer?

	let reel: HighlightReel
	let reload: () async -> Void

	@State private var index: Int = 0
	@State private var progress: Double = 0
	@State private var isPaused = false
	@State private var audioPlayer: AVPlayer? = nil
	@State private var slideTask: Task<Void, Never>? = nil
	@State private var isRequestingVideo = false
	@State private var toast = ToastState()
	@State private var containerWidth: CGFloat = 0

	/// Slides without an audio excerpt (intro, stat, outro) hold for this long.
	private static let defaultSlideSeconds: Double = 5

	private var slide: ReelSlide? {
		self.reel.slides.indices.contains(self.index) ? self.reel.slides[self.index] : nil
	}

	var body: some View {
		ZStack {
			DTColor.background.ignoresSafeArea()

			if let slide {
				self.background(for: slide)
				self.content(for: slide)
			}

			VStack {
				self.progressBars
					.padding(.horizontal)
					.padding(.top, 8)

				Spacer()

				self.videoControls
					.padding(.horizontal)
					.padding(.bottom, 28)
			}
		}
		.toast(self.toast)
		.contentShape(Rectangle())
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { self.containerWidth = $0 }
		.onTapGesture { location in
			self.handleTap(at: location)
		}
		.onLongPressGesture(minimumDuration: 0.2) {
			self.togglePause()
		}
		.task {
			// The reel has its own audio; leaving the main player running would talk over it.
			if PlayerEngine.shared.isPlaying {
				PlayerEngine.shared.togglePlay()
			}
			self.startSlide()
		}
		.onDisappear {
			self.slideTask?.cancel()
			self.audioPlayer?.pause()
			self.audioPlayer = nil
		}
	}

	// MARK: - Slide rendering

	@ContentBuilder
	private func background(for slide: ReelSlide) -> some View {
		if let cover = slide.cover.flatMap(URL.init(string:)) {
			AsyncImage(url: cover) { image in
				image
					.resizable()
					.scaledToFill()
					.blur(radius: 40)
					.overlay(Color.black.opacity(0.45))
			} placeholder: {
				Rectangle().fill(DTColor.accentGradient)
			}
			.ignoresSafeArea()
		} else {
			Rectangle().fill(DTColor.accentGradient)
				.ignoresSafeArea()
		}
	}

	@ContentBuilder
	private func content(for slide: ReelSlide) -> some View {
		VStack(spacing: 18) {
			Spacer()

			if slide.kind == .intro || slide.kind == .outro, !self.reel.collage.isEmpty {
				self.collage
			} else if let cover = slide.cover.flatMap(URL.init(string:)) {
				CoverImage(url: cover, cornerRadius: slide.kind == .artist ? DTRadius.pill : 18)
					.frame(width: 220, height: 220)
					.shadow(radius: 20)
			}

			if let label = slide.label {
				Text(self.localizedLabel(label))
					.font(DTFont.system(14))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.multilineTextAlignment(.center)
			}

			if let value = slide.value {
				Text(value)
					.font(DTFont.serif(56))
					.foregroundStyle(DTColor.textPrimary)
					.multilineTextAlignment(.center)
					.minimumScaleFactor(0.5)
					.lineLimit(2)
			}

			if let title = slide.title {
				Text(title)
					.font(DTFont.serif(30))
					.foregroundStyle(DTColor.textPrimary)
					.multilineTextAlignment(.center)
					.lineLimit(2)
			}

			if let subtitle = slide.subtitle {
				Text(subtitle)
					.font(DTFont.system(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.multilineTextAlignment(.center)
					.lineLimit(2)
			}

			Spacer()
			Spacer()
		}
		.padding(.horizontal, 32)
	}

	@ContentBuilder
	private var collage: some View {
		LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
			ForEach(self.reel.collage.prefix(9), id: \.self) { cover in
				CoverImage(url: URL(string: cover), cornerRadius: 8)
					.frame(height: 80)
			}
		}
		.frame(maxWidth: 260)
	}

	@ContentBuilder
	private var progressBars: some View {
		HStack(spacing: 4) {
			ForEach(self.reel.slides.indices, id: \.self) { slideIndex in
				GeometryReader { proxy in
					ZStack(alignment: .leading) {
						Capsule()
							.fill(DTColor.textPrimary.opacity(0.25))

						Capsule()
							.fill(DTColor.textPrimary)
							.frame(width: proxy.size.width * self.fill(for: slideIndex))
					}
				}
				.frame(height: 3)
			}
		}
	}

	private func fill(for slideIndex: Int) -> Double {
		if slideIndex < self.index { return 1 }
		if slideIndex > self.index { return 0 }
		return self.progress
	}

	// MARK: - Server-rendered MP4

	@ContentBuilder
	private var videoControls: some View {
		switch self.reel.reelStatus {
			case .ready where self.reel.hasVideo:
				if let url = self.server?.reelVideoURL(year: self.reel.year) {
					ShareLink(item: url) {
						Label(String(localized: "insights-share-video"), systemImage: "square.and.arrow.up")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.hollow())
				}
			case .queued, .rendering:
				Label(String(localized: "insights-reel-rendering"), systemImage: "hourglass")
					.font(DTFont.system(13))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
					.task {
						await self.pollRenderStatus()
					}
			case .failed:
				VStack(spacing: 6) {
					Text(self.reel.reelError ?? String(localized: "insights-reel-failed"))
						.font(DTFont.system(12))
						.foregroundStyle(DTColor.statusFailure)
						.multilineTextAlignment(.center)

					self.requestVideoButton
				}
			default:
				self.requestVideoButton
		}
	}

	@ContentBuilder
	private var requestVideoButton: some View {
		Button {
			self.requestVideo()
		} label: {
			if self.isRequestingVideo {
				ProgressView()
					.tint(DTColor.textPrimary)
					.frame(maxWidth: .infinity)
			} else {
				Label(String(localized: "insights-render-video"), systemImage: "film")
					.frame(maxWidth: .infinity)
			}
		}
		.buttonStyle(.hollow())
		.disabled(self.isRequestingVideo)
	}

	private func requestVideo() {
		guard let server else { return }
		self.isRequestingVideo = true

		Task {
			do {
				_ = try await server.send(Insights.requestReelVideo(year: self.reel.year)) as RequestReelVideoResponse
				await self.reload()
			} catch {
				self.toast.failure(error)
			}
			self.isRequestingVideo = false
		}
	}

	/// Re-reads the manifest until the render leaves the queued/rendering state — reels are produced one
	/// at a time server-side, so there's nothing to subscribe to, only this poll.
	private func pollRenderStatus() async {
		guard let server else { return }

		while !Task.isCancelled {
			try? await Task.sleep(for: .seconds(10))
			guard let updated = try? await server.send(Insights.reel(year: self.reel.year)) as HighlightReel else { continue }
			if updated.reelStatus != .queued && updated.reelStatus != .rendering {
				await self.reload()
				return
			}
		}
	}

	// MARK: - Playback

	/// `ReelSlide.label` is an i18n key rather than display text, so an unknown key falls back to the key
	/// itself rather than showing nothing.
	private func localizedLabel(_ key: String) -> String {
		let localized = String(localized: String.LocalizationValue(key))
		return localized.isEmpty ? key : localized
	}

	private func startSlide() {
		self.slideTask?.cancel()
		self.progress = 0
		self.audioPlayer?.pause()
		self.audioPlayer = nil

		guard let slide else { return }

		let duration: Double
		if let excerpt = slide.excerptSeconds, excerpt > 0 {
			duration = Double(excerpt)
		} else {
			duration = Self.defaultSlideSeconds
		}

		if let trackId = slide.trackId, let url = self.server?.mediaStreamURL(id: trackId) {
			let player = AVPlayer(url: url)
			if let start = slide.excerptStartSeconds, start > 0 {
				player.seek(to: CMTime(seconds: Double(start), preferredTimescale: 600))
			}
			player.play()
			self.audioPlayer = player
		}

		self.slideTask = Task {
			let step: Double = 0.05
			var elapsed: Double = 0

			while elapsed < duration {
				try? await Task.sleep(for: .seconds(step))
				if Task.isCancelled { return }
				if self.isPaused { continue }

				elapsed += step
				self.progress = min(elapsed / duration, 1)
			}

			self.advance(by: 1)
		}
	}

	private func advance(by offset: Int) {
		let next = self.index + offset
		guard next >= 0 else { return }
		guard next < self.reel.slides.count else {
			self.slideTask?.cancel()
			self.audioPlayer?.pause()
			self.progress = 1
			return
		}

		self.index = next
		self.startSlide()
	}

	private func togglePause() {
		self.isPaused.toggle()
		if self.isPaused {
			self.audioPlayer?.pause()
		} else {
			self.audioPlayer?.play()
		}
	}

	private func handleTap(at location: CGPoint) {
		self.advance(by: location.x < self.containerWidth / 3 ? -1 : 1)
	}
}
