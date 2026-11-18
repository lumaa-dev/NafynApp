// Made by Lumaa

import SwiftUI
import Safyn

/// One personalized mix (`Recommendations.mix`): the familiar tracks play like a playlist, the suggestions
/// are catalogue recordings - previewed for 30 seconds and requested from here.
struct MixDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	let mixId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Recommendations.mix(id: self.mixId)) as MixDetail
		} skeleton: {
			AnyView(SkeletonTrackRows())
		} content: { mix, _ in
			MixDetailContent(mix: mix)
		}
		.navigationTitle(String(localized: "mix-made-for-you"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct MixDetailContent: View {
	@Environment(\.server) private var server: NafynServer?

	let mix: MixDetail

	@State private var requested: Set<String> = []
	@State private var toast = ToastState()

	private var familiar: [MediaRow] {
		self.mix.tracks.compactMap(\.media)
	}

	private var suggestions: [MixSuggestion] {
		self.mix.tracks.compactMap(\.suggestion)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				self.header

				LazyVStack(spacing: 0) {
					ForEach(self.mix.tracks) { track in
						if let media = track.media {
							TrackRow(
								coverURL: media.listCoverURL,
								title: media.title,
								subtitle: "\(media.artistName) · \(track.reason.text)",
								duration: media.duration
							) {
								self.play(from: media)
							}
							.libraryItemMenu(item: track.inLibrary ? .track(id: media.id) : nil, play: nil)
						} else if let suggestion = track.suggestion {
							self.suggestionRow(suggestion, reason: track.reason)
						}
					}
				}
			}
			.padding(.horizontal)
			.padding(.vertical)
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.contentColumn()
		.background(DTColor.background.ignoresSafeArea())
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
			RecommendationFeedback.shared.attributeMix(id: self.mix.id, mediaIds: self.familiar.map(\.id), recordingIds: self.suggestions.map(\.recordingId))
		}
		.onDisappear {
			PreviewPlayer.shared.stop()
		}
		.toast(self.toast)
	}

	@ContentBuilder
	private var header: some View {
		VStack(alignment: .leading, spacing: 10) {
			MixCover(covers: self.mix.covers, size: 1000)
				.frame(maxWidth: 260)

			Text(self.mix.label.localizedTitle)
				.font(DTFont.serif(40))
				.foregroundStyle(DTColor.textPrimary)

			Text(String(localized: "mix-summary-\(self.familiar.count)-\(self.suggestions.count)"))
				.font(DTFont.system(14))
				.foregroundStyle(DTColor.textPrimary.opacity(0.7))

			if !self.mix.topArtists.isEmpty {
				Text(self.mix.topArtists.prefix(4).joined(separator: ", "))
					.font(DTFont.system(14))
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))
			}

			if !self.familiar.isEmpty {
				HStack(spacing: 10) {
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
					.buttonStyle(.filled())
				}
			}
		}
	}

	private func suggestionRow(_ suggestion: MixSuggestion, reason: MixTrackReason) -> some View {
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
							.foregroundStyle(DTColor.textPrimary)
							.lineLimit(1)
						Text(suggestion.artist)
							.font(DTFont.serif(15))
							.foregroundStyle(DTColor.textPrimary.opacity(0.7))
							.lineLimit(1)
						Text("\(String(localized: "mix-suggested")) · \(reason.text)")
							.font(DTFont.serifItalic(14))
							.foregroundStyle(DTColor.textPrimary.opacity(0.7))
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
					.frame(width: 36, height: 36)
			}
			.buttonStyle(.hollow())
			.clipShape(Circle())
			.disabled(preview.unavailableIds.contains(id))

			Button(String(localized: "request")) {
				self.request(suggestion)
			}
			.buttonStyle(.hollow())
			.disabled(self.requested.contains(id) || NetworkMonitor.shared.isOffline)
		}
		.padding(.vertical, 6)
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
