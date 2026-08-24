// Made by Lumaa

import SwiftUI
import TextFlowKit
import Safyn

/// Word/syllable-level "karaoke" lyrics, mirroring Apple Music Sing — ported from the Amber team's own
/// working `TextFlowKit` integration (`LyricsViewer.swift`), adapted from `AmberLyrics` to Safyn's
/// `Lyrics` model (structurally identical: paragraphs → lines → timed segments).
struct LyricsPanel: View {
	@Environment(\.server) private var server: NafynServer?

	/// `UserDefaults` key shared with the "appearance" toggle in `SettingsView` that swaps this panel's
	/// serif display font for the system font.
	static let useSystemFontKey = "lyricsUseSystemFont"

	/// Segments whose duration is at least this long get the glow + emphasis treatment.
	public static let longThreshold: TimeInterval = 1.5

	static func font(_ size: CGFloat, useSystemFont: Bool) -> Font {
		useSystemFont ? DTFont.system(size, weight: .bold) : DTFont.serif(size)
	}

	/// How long the user must go without touching the scroll view before auto-scroll resumes.
	private static let scrollResumeDelay: TimeInterval = 2.0

	var trackId: String

	@State private var isUserScrolling = false
	@State private var scrollResumeTask: Task<Void, Never>? = nil
	@AppStorage(LyricsPanel.useSystemFontKey) private var useSystemFont = false

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Library.lyrics(id: self.trackId)) as Lyrics
		} content: { lyrics, _ in
			ScrollViewReader { proxy in
				ScrollView {
					VStack(alignment: .leading, spacing: 18) {
						ForEach(lyrics.paragraphs, id: \.id) { paragraph in
							ForEach(paragraph.lines, id: \.id) { line in
								self.lineView(line)
									.id(line.id)
							}
						}
					}
					.padding()
				}
				.scrollEdgeEffectStyle(.soft, for: .all)
				.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
					self.markUserScrolling {
						if let id = self.activeLineId(in: lyrics) {
							withAnimation(.smooth(duration: 0.4)) {
								proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35))
							}
						}
					}
				})
				.onChange(of: self.activeLineId(in: lyrics)) { _, newId in
					guard let newId, !self.isUserScrolling else { return }
					withAnimation(.smooth(duration: 0.4)) {
						proxy.scrollTo(newId, anchor: UnitPoint(x: 0.5, y: 0.35))
					}
				}
			}
		}
	}

	private func markUserScrolling(onResume: @escaping () -> Void) {
		self.isUserScrolling = true
		self.scrollResumeTask?.cancel()
		self.scrollResumeTask = Task {
			try? await Task.sleep(for: .seconds(Self.scrollResumeDelay))
			guard !Task.isCancelled else { return }
			self.isUserScrolling = false
			onResume()
		}
	}

	private func activeLineId(in lyrics: Lyrics) -> String? {
		let currentTime = PlayerEngine.shared.currentTime
		for paragraph in lyrics.paragraphs {
			for line in paragraph.lines {
				if currentTime >= line.startTime && currentTime < line.endTime {
					return line.id
				}
			}
		}
		return nil
	}

	@ViewBuilder
	private func lineView(_ line: Lyrics.Line) -> some View {
		let currentTime = PlayerEngine.shared.currentTime
		let isBackground = line.type.kind == .background
		let isAlt = line.type.alt
		let isActive = currentTime >= line.startTime && currentTime < line.endTime
		let sizeMultiplier: CGFloat = isBackground ? 0.75 : 1.0

		Button {
			PlayerEngine.shared.seek(to: line.startTime)
		} label: {
			Group {
				if line.segments.isEmpty {
					Text(line.text)
						.font(Self.font(isBackground ? 27 : 32, useSystemFont: self.useSystemFont))
						.foregroundStyle(isActive ? DTColor.textPrimary : DTColor.textPrimary.opacity(0.4))
						.multilineTextAlignment(isAlt ? .trailing : .leading)
				} else {
					// Group syllables into their words (splitting on `endsWord`) so `FlowLayout` only
					// wraps whole words onto new lines — syllables within a word sit flush against each
					// other, matching how they read in `line.text`.
					FlowLayout(alignment: isAlt ? .trailing : .leading, spacing: 5) {
						ForEach(Self.wordGroups(from: line.segments), id: \.self) { group in
							HStack(spacing: 0) {
								ForEach(group, id: \.id) { segment in
									SegmentTextView(segment: segment, isBackground: isBackground, useSystemFont: self.useSystemFont)
								}
							}
						}
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: isAlt ? .trailing : .leading)
			.scaleEffect((isActive ? 1.0 : 0.85) * sizeMultiplier, anchor: isAlt ? .trailing : .leading)
			.animation(.smooth(duration: 0.3), value: isActive)
		}
		.buttonStyle(.plain)
	}

	private static func wordGroups(from segments: [Lyrics.Segment]) -> [[Lyrics.Segment]] {
		guard !segments.isEmpty else { return [] }
		var groups: [[Lyrics.Segment]] = []
		var current: [Lyrics.Segment] = []

		for segment in segments {
			current.append(segment)
			if segment.endsWord {
				groups.append(current)
				current = []
			}
		}
		if !current.isEmpty {
			groups.append(current)
		}

		return groups
	}
}

/// One word/syllable within a lyric line — sweeps its `TextFlow` reveal to full over its own timed
/// duration once active, exactly like `usePlayer`'s web-side highlight but rendered as an animated
/// gradient sweep across the glyph instead of a discrete color flip.
private struct SegmentTextView: View {
	let segment: Lyrics.Segment
	let isBackground: Bool
	let useSystemFont: Bool

	var body: some View {
		let currentTime = PlayerEngine.shared.currentTime
		let isActive = currentTime >= self.segment.startTime && currentTime < self.segment.endTime
		let duration = self.segment.endTime - self.segment.startTime
		let isLong = duration >= LyricsPanel.longThreshold
		let txt = Text(self.segment.text).font(LyricsPanel.font(self.isBackground ? 22 : 32, useSystemFont: self.useSystemFont))

		let isPlayed = currentTime >= self.segment.endTime

		Group {
			if isLong {
				let elapsed = max(0, currentTime - self.segment.startTime)
				let rawT = duration > 0 ? Float(elapsed / duration) : 0
				let clampedT = isActive ? max(0, min(1, rawT)) : 0
				let glowProgress: Float = isActive ? Float(sin(Double.pi * Double(clampedT))) : 0

				TextFlow(
					txt,
					progress: .constant((isActive || isPlayed) ? 1.0 : 0.0),
					glowProgress: .constant(glowProgress),
					glowStrength: 1.2
				)
				.animation(.linear(duration: isActive ? duration : 0), value: clampedT)
			} else {
				TextFlow(txt, progress: .constant((isActive || isPlayed) ? 1.0 : 0.0))
					.animation(.linear(duration: isActive ? duration : 0), value: isActive)
			}
		}
		.foregroundStyle(DTColor.textPrimary)
	}
}
