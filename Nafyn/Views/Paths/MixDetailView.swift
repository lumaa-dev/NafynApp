// Made by Lumaa

import SwiftUI
import Safyn

/// One personalized mix (`Recommendations.mix`): the familiar tracks play like a playlist, the suggestions
/// are catalogue recordings - previewed for 30 seconds and requested from here.
struct MixDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	let mixId: String

	var body: some View {
		AsyncContentView(placeholder: MixDetail.placeholder) {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Recommendations.mix(id: self.mixId)) as MixDetail
		} content: { mix, _ in
			MixDetailContent(mix: mix)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct MixDetailContent: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.colorScheme) private var colorScheme
	/// Drawn as the screen's skeleton with placeholder data: no feedback is attributed (DESIGN.md "Skeleton loading").
	@Environment(\.isSkeleton) private var isSkeleton

	let mix: MixDetail

	@State private var requested: Set<String> = []
	@State private var toast = ToastState()
	/// The first cover's dominant colours (hex), for the cover-themed screen; `nil` until read.
	@State private var imageColors: [String]? = nil

	private var familiar: [MediaRow] {
		self.mix.tracks.compactMap(\.media)
	}

	private var suggestions: [MixSuggestion] {
		self.mix.tracks.compactMap(\.suggestion)
	}

	/// The cover the screen takes its colours from: the grid's first.
	private var leadCoverURL: URL? {
		self.mix.covers.first.flatMap { $0.contains("/art/") ? $0.coverArtURL(size: 250) : URL(string: $0) }
	}

	var body: some View {
		let palette = CoverPalette(imageColors: self.imageColors, colorScheme: self.colorScheme)

		// The same layout as an album or a playlist (DESIGN.md "Track/Album Detail view"): the mix's covers edge to
		// edge with its title on them, coloured after them, then the actions and the tracks; two panes when the window
		// has room.
		AdaptiveCoverDetail(palette: palette) {
			self.header(palette: palette)
		} compact: {
			self.details(palette: palette)
			self.actions
			self.trackList(palette: palette)
		} primary: {
			self.details(palette: palette)
		} secondary: {
			self.actions
			self.trackList(palette: palette)
		}
		.animation(.easeOut(duration: 0.25), value: self.imageColors)
		.task(id: self.mix.covers.first) {
			guard !self.isSkeleton else { return }
			self.imageColors = await Self.hexColors(of: self.leadCoverURL)
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					self.refresh()
				} label: {
					Label(String(localized: "mix-refresh"), systemImage: "arrow.clockwise")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
		.onAppear {
			guard !self.isSkeleton else { return }
			RecommendationFeedback.shared.attributeMix(id: self.mix.id, mediaIds: self.familiar.map(\.id), recordingIds: self.suggestions.map(\.recordingId))
		}
		.onDisappear {
			PreviewPlayer.shared.stop()
		}
		.toast(self.toast)
	}

	/// The four covers as the header's picture, the mix's title and "Made for you" on them.
	private func header(palette: CoverPalette) -> some View {
		CoverHeader(url: nil, palette: palette, artwork: AnyView(MixCover(covers: self.mix.covers, size: 1000, cornerRadius: 0))) {
			Text(self.mix.label.localizedTitle)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)

			Text(String(localized: "mix-made-for-you"))
				.font(DTFont.serifItalic(20))
				.foregroundStyle(palette.primary)
		}
	}

	/// How many tracks of each kind, and the artists the mix is built around.
	@ViewBuilder
	private func details(palette: CoverPalette) -> some View {
		Text(String(localized: "mix-summary-\(self.familiar.count)-\(self.suggestions.count)"))
			.font(DTFont.system(16))
			.foregroundStyle(palette.secondary)

		if !self.mix.topArtists.isEmpty {
			Text(self.mix.topArtists.prefix(4).joined(separator: ", "))
				.font(DTFont.system(16))
				.foregroundStyle(palette.secondary)
		}
	}

	/// Play / Shuffle the familiar tracks (the suggestions are previews, not playable yet), like a playlist's.
	@ViewBuilder
	private var actions: some View {
		if !self.familiar.isEmpty {
			HStack {
				Button {
					guard let first = self.familiar.first else { return }
					PlaybackSource.play(first, queue: self.familiar)
				} label: {
					Label(String(localized: "play"), systemImage: "play.fill")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())

				Button {
					let shuffled = self.familiar.shuffled()
					guard let first = shuffled.first else { return }
					PlaybackSource.play(first, queue: shuffled)
				} label: {
					Label(String(localized: "shuffle"), systemImage: "shuffle")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())
			}
		}
	}

	private func trackList(palette: CoverPalette) -> some View {
		LazyVStack(spacing: 0) {
			ForEach(Array(self.mix.tracks.enumerated()), id: \.element.id) { index, track in
				Group {
					if let media = track.media {
						TrackRow(
							coverURL: media.listCoverURL,
							title: media.title,
							subtitle: "\(media.artistName) · \(track.reason.text)",
							duration: media.duration,
							verticalPadding: 8
						) {
							self.play(from: media)
						}
						.libraryItemMenu(item: track.inLibrary ? .track(id: media.id) : nil, play: nil)
					} else if let suggestion = track.suggestion {
						self.suggestionRow(suggestion, reason: track.reason, palette: palette)
					}
				}

				if index < self.mix.tracks.count - 1 {
					Divider()
						.overlay(palette.secondary.opacity(0.3))
				}
			}
		}
	}

	/// The first cover's dominant colours as hex, for ``CoverPalette`` (as a playlist's image).
	private static func hexColors(of url: URL?) async -> [String]? {
		guard url != nil else { return nil }
		let colors = await CoverPaletteExtractor.palette(for: url)
		return colors.compactMap { color in
			var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
			guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
			return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
		}
	}

	private func suggestionRow(_ suggestion: MixSuggestion, reason: MixTrackReason, palette: CoverPalette) -> some View {
		let preview = PreviewPlayer.shared
		let id = suggestion.recordingId
		return HStack(spacing: 12) {
			Button {
				Navigator.shared.send(to: .track(id: id))
			} label: {
				HStack(spacing: 12) {
					CoverImage(url: suggestion.coverArt.flatMap { $0.contains("/art/") ? $0.coverArtURL(size: 250) : URL(string: $0) }, cornerRadius: 6)
						.frame(width: 50, height: 50)
					VStack(alignment: .leading, spacing: 2) {
						Text(suggestion.title)
							.font(DTFont.serif(18))
							.foregroundStyle(palette.primary)
							.lineLimit(1)
						Text(suggestion.artist)
							.font(DTFont.serif(15))
							.foregroundStyle(palette.secondary)
							.lineLimit(1)
						Text("\(String(localized: "mix-suggested")) · \(reason.text)")
							.font(DTFont.serifItalic(14))
							.foregroundStyle(palette.secondary)
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			// DESIGN.md "Icon-only buttons": a circle, an accessible label (and no text to explain it)
			Button {
				preview.toggle(tid: id, server: self.server)
			} label: {
				Label(String(localized: preview.isActive(id) ? "stop-preview" : "play-preview"), systemImage: preview.isActive(id) ? "stop.fill" : "play.fill")
					.labelStyle(.iconOnly)
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(palette.primary)
					.frame(width: 36, height: 36)
					// the hollow style pads 48pt sideways: a circle of its own keeps the button 1:1
					.overlay(Circle().strokeBorder(palette.primary, lineWidth: 1))
					.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.disabled(preview.unavailableIds.contains(id))

			Button(String(localized: "request")) {
				self.request(suggestion)
			}
			.buttonStyle(.hollow())
			.disabled(self.requested.contains(id) || NetworkMonitor.shared.isOffline)
		}
		.padding(.vertical, 8)
	}

	private func play(from media: MediaRow) {
		let queue = self.familiar
		guard let index = queue.firstIndex(where: { $0.id == media.id }) else { return }
		PlaybackSource.play(queue[index], queue: queue)
	}

	/// The button disables before the call goes out, and comes back only if it failed.
	private func request(_ suggestion: MixSuggestion) {
		guard let server else { return }
		self.requested.insert(suggestion.recordingId)
		Task {
			do {
				_ = try await server.send(Request.create(id: suggestion.recordingId, type: .track)) as NafynRequest
				RecommendationFeedback.shared.requested(recordingId: suggestion.recordingId)
				self.toast.success(String(localized: "request-sent"))
				await PushManager.shared.requestAuthorizationIfNeeded()
			} catch {
				self.requested.remove(suggestion.recordingId)
				self.toast.failure(error)
			}
		}
	}

	private func refresh() {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Recommendations.refreshMixes) as MixRefreshResponse
				self.toast.success(String(localized: "mix-refresh-started"))
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
