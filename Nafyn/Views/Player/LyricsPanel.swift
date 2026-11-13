// Made by Lumaa

import SwiftUI
import TextFlowKit
import NaturalLanguage
import FoundationModels
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
		useSystemFont ? DTFont.system(size, weight: .bold) : DTFont.serif(size).bold()
	}

	/// How long the user must go without touching the scroll view before auto-scroll resumes.
	private static let scrollResumeDelay: TimeInterval = 2.0

	var trackId: String

	@State private var isUserScrolling = false
	@State private var scrollResumeTask: Task<Void, Never>? = nil

	// MARK: Translation

	/// What the lyrics are sung in, detected once they have loaded; `nil` until then or when unsure.
	@State private var sourceLanguage: Locale.Language? = nil
	/// Translated text per line ID, filled by the first tap on the translate button.
	@State private var translations: [String: String] = [:]
	@State private var isTranslating = false
	@State private var showsTranslation = false
	@AppStorage(LyricsPanel.useSystemFontKey) private var useSystemFont = false

	/// DESIGN.md "Lyrics Panel": tap-and-hold a paragraph opens "Share Lyrics" on it.
	@State private var sharing: SharedParagraph?
	/// A hold just opened the share sheet: the line's own tap (seek) that ends it is ignored.
	@State private var heldParagraph = false

	private struct SharedParagraph: Identifiable {
		let lyrics: Lyrics
		let paragraphId: String
		var id: String { self.paragraphId }
	}

	var body: some View {
		AsyncContentView(
			load: { () async throws -> Lyrics? in
				guard let server else { throw NafynError.unauthenticated }
				do {
					return try await server.send(Library.lyrics(id: self.trackId)) as Lyrics
				} catch NafynError.server(let statusCode, _) where statusCode == 404 {
					// a track without lyrics is not an error worth a retry button
					return nil
				}
			},
			skeleton: { AnyView(SkeletonTextLines()) },
			showsBackground: false
		) { lyrics, _ in
			if let lyrics {
				self.lyricsView(lyrics)
			} else {
				Text("no-lyrics")
					.font(DTFont.system(18))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					.multilineTextAlignment(.center)
					.padding()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
	}

	@ViewBuilder
	private func lyricsView(_ lyrics: Lyrics) -> some View {
		ScrollViewReader { proxy in
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					ForEach(lyrics.paragraphs, id: \.id) { paragraph in
						VStack(alignment: .leading, spacing: 18) {
							ForEach(paragraph.lines, id: \.id) { line in
								self.lineView(line)
									.id(line.id)
							}
						}
						.simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
							self.heldParagraph = true
							Haptics.hold()
							self.sharing = SharedParagraph(lyrics: lyrics, paragraphId: paragraph.id)
							// a hold that didn't end on a line leaves no tap to swallow
							Task {
								try? await Task.sleep(for: .seconds(1))
								self.heldParagraph = false
							}
						})
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
			.overlay(alignment: .topTrailing) {
				if self.canTranslate {
					self.translateButton(lyrics)
				}
			}
			.task(id: self.trackId) {
				self.sourceLanguage = Self.detectLanguage(of: lyrics)
			}
			.sheet(item: self.$sharing) { shared in
				LyricsShareSheet(
					lyrics: shared.lyrics,
					track: PlaybackSource.track?.id == self.trackId ? PlaybackSource.track : nil,
					initialParagraphId: shared.paragraphId
				)
			}
		}
	}

	// MARK: - Translation

	/// The language the app is displayed in (the user's choice for Nafyn, which can differ from the system's).
	private static var appLanguage: Locale.Language {
		Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
	}

	/// The on-device model, with the guardrails relaxed for transforming text the user already has: lyrics
	/// contain profanity and violence that the default guardrails would refuse to translate.
	private static var permissiveModel: SystemLanguageModel {
		SystemLanguageModel(guardrails: .permissiveContentTransformations)
	}

	/// Shown only on Apple Intelligence devices (model available, both languages supported) and only when the
	/// lyrics are in another language than the app's.
	private var canTranslate: Bool {
		guard let source = self.sourceLanguage else { return false }
		guard source.languageCode != Self.appLanguage.languageCode else { return false }

		let model = SystemLanguageModel.default
		guard model.availability == .available else { return false }

		let supported = model.supportedLanguages
		return supported.contains { $0.languageCode == source.languageCode }
			&& supported.contains { $0.languageCode == Self.appLanguage.languageCode }
	}

	private static func detectLanguage(of lyrics: Lyrics) -> Locale.Language? {
		let sample = Self.lines(of: lyrics).prefix(40).map(\.text).joined(separator: "\n")
		guard !sample.isEmpty else { return nil }

		let recognizer = NLLanguageRecognizer()
		recognizer.processString(sample)
		guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.5 else { return nil }
		return Locale.Language(identifier: language.rawValue)
	}

	private static func lines(of lyrics: Lyrics) -> [Lyrics.Line] {
		lyrics.paragraphs.flatMap(\.lines).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	}

	private func translateButton(_ lyrics: Lyrics) -> some View {
		Button {
			self.translateTapped(lyrics)
		} label: {
			Group {
				if self.isTranslating {
					ProgressView()
						.tint(DTColor.textPrimary)
				} else {
					Label(String(localized: "translate"), systemImage: "translate")
						.labelStyle(.iconOnly)
						.foregroundStyle(self.showsTranslation ? DTColor.accentStart : DTColor.textPrimary.opacity(0.85))
				}
			}
			.frame(width: 22, height: 22)
		}
		.buttonStyle(.glass)
		.buttonBorderShape(.circle)
		.tint(Color.primary)
		.disabled(self.isTranslating)
		.padding(.trailing, 8)
		.accessibilityLabel(String(localized: "translate"))
	}

	/// The first tap generates the translation (and disables the button meanwhile); after that it is a toggle.
	private func translateTapped(_ lyrics: Lyrics) {
		guard !self.isTranslating else { return }

		if !self.translations.isEmpty {
			withAnimation(.smooth(duration: 0.3)) {
				self.showsTranslation.toggle()
			}
			return
		}

		guard let source = self.sourceLanguage else { return }
		self.isTranslating = true

		Task {
			defer { self.isTranslating = false }

			let result = await Self.translate(Self.lines(of: lyrics), from: source, to: Self.appLanguage)
			guard !result.isEmpty else { return }

			self.translations = result
			withAnimation(.smooth(duration: 0.3)) {
				self.showsTranslation = true
			}
		}
	}

	/// How many lines already translated go with each batch as context.
	private static let translationContextLines = 12

	/// Translates in batches that fit the model's context window, one line out per line in. A batch that
	/// fails is skipped (its lines just stay untranslated) rather than losing the whole song.
	///
	/// Every batch is a new session (one session for the whole song would overflow the on-device context window),
	/// so each one is handed the lines just before it, with their translation, as context: a batch translated
	/// alone lost the song's subject, its pronouns and the words already chosen for its recurring lines.
	private static func translate(_ lines: [Lyrics.Line], from source: Locale.Language, to target: Locale.Language) async -> [String: String] {
		let describe: (Locale.Language) -> String = { Locale.current.localizedString(forLanguageCode: $0.minimalIdentifier) ?? $0.minimalIdentifier }
		let instructions = """
		You translate song lyrics from \(describe(source)) to \(describe(target)). \
		Translate faithfully, including profanity and slang, without censoring, softening or commenting. \
		The input has one numbered line per lyric line, like "3: text". Answer with the same numbers and one \
		translated line for each, in the same "3: text" form, and nothing else. \
		The input may start with the lines that come just before, already translated, after "Previous lines:" \
		as "original => translation": they are context only. Keep the meaning, the voice and the word choices \
		consistent with them (a line that repeats is translated the same way), and never answer them again.
		"""

		var result: [String: String] = [:]
		// (original, translation) of every line translated so far, in order
		var translated: [(String, String)] = []

		for batch in lines.chunked(into: 20) {
			let numbered = batch.enumerated().map { "\($0.offset + 1): \($0.element.text)" }.joined(separator: "\n")
			let context = translated.suffix(Self.translationContextLines).map { "\($0.0) => \($0.1)" }
			let prompt = context.isEmpty
				? numbered
				: "Previous lines:\n\(context.joined(separator: "\n"))\n\nTranslate:\n\(numbered)"
			let session = LanguageModelSession(model: Self.permissiveModel, instructions: instructions)

			guard let response = try? await session.respond(to: prompt) else { continue }

			for answer in response.content.split(separator: "\n") {
				guard let colon = answer.firstIndex(of: ":"),
					  let number = Int(answer[..<colon].trimmingCharacters(in: .whitespaces)),
					  batch.indices.contains(number - 1)
				else { continue }

				let text = answer[answer.index(after: colon)...].trimmingCharacters(in: .whitespaces)
				if !text.isEmpty {
					result[batch[number - 1].id] = text
				}
			}

			for line in batch {
				if let text = result[line.id] {
					translated.append((line.text, text))
				}
			}
		}

		return result
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
		let currentTime = PlaybackSource.currentTime
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
		let currentTime = PlaybackSource.currentTime
		let isBackground = line.type.kind == .background
		let isAlt = line.type.alt
		let isActive = currentTime >= line.startTime && currentTime < line.endTime
		let sizeMultiplier: CGFloat = isBackground ? 0.75 : 1.0

		Button {
			// the end of a hold that opened "Share Lyrics" is not a tap to seek
			if self.heldParagraph {
				self.heldParagraph = false
				return
			}
			PlaybackSource.seek(to: line.startTime)
		} label: {
			VStack(alignment: isAlt ? .trailing : .leading, spacing: 6) {
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

			// smaller and a step dimmer than the lyric above it
			if self.showsTranslation, let translated = self.translations[line.id] {
				Text(translated)
					.font(Self.font(isBackground ? 17 : 20, useSystemFont: self.useSystemFont))
					.foregroundStyle(DTColor.textPrimary.opacity(isActive ? 0.55 : 0.3))
					.multilineTextAlignment(isAlt ? .trailing : .leading)
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
		let currentTime = PlaybackSource.currentTime
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

private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		stride(from: 0, to: self.count, by: size).map { Array(self[$0..<Swift.min($0 + size, self.count)]) }
	}
}
