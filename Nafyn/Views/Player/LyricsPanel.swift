// Made by Lumaa

import SwiftUI
import NaturalLanguage
import FoundationModels
import Safyn

/// Word/syllable-level "karaoke" lyrics, mirroring Apple Music Sing. The server sends Braccato's `Lyric[]`
/// (Safyn's `Lyrics`); `LyricsLayout` turns it into the paragraphs → lines → timed segments this panel draws,
/// and `KaraokeText` (`Lyrics/Rendering/`) sweeps each line word by word.
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

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@State private var isUserScrolling = false
	@State private var clock = LyricsClock()
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
		let lyrics: LyricsLayout
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
			if let layout = lyrics.map(LyricsLayout.init), !layout.paragraphs.isEmpty {
				self.lyricsView(layout)
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
	private func lyricsView(_ lyrics: LyricsLayout) -> some View {
		let activeBreak = self.activeBreak(in: lyrics)

		ScrollViewReader { proxy in
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					ForEach(lyrics.paragraphs, id: \.id) { paragraph in
						// only while it plays: the next lyric takes its place when it ends
						if let pause = paragraph.breakBefore, pause == activeBreak {
							self.breakView(pause)
								.id(pause.id)
								.transition(self.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
						}

						VStack(alignment: .leading, spacing: 18) {
							ForEach(paragraph.lines, id: \.id) { line in
								self.lineView(line, synced: lyrics.isSynced)
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

					if let credit = lyrics.credit {
						self.creditView(credit)
					}
				}
				.padding()
				.animation(.easeOut(duration: 0.25), value: activeBreak)
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

	// MARK: - Credit

	/// A provider's licence credit (Unison: "Lyrics from Unison · submitted by <name>"), each part linked.
	/// DESIGN.md "Links": underlined, italic serif, and a tap opens the page in a web sheet, not Safari.
	@ViewBuilder
	private func creditView(_ credit: Lyrics.Credit) -> some View {
		Text(Self.creditText(credit))
			.font(DTFont.serif(16))
			.foregroundStyle(DTColor.textPrimary.opacity(0.85))
			.tint(DTColor.textPrimary)
			.padding(.top, 12)
			.environment(\.openURL, OpenURLAction { url in
				Navigator.shared.sheet = Navigator.Paths.web(url: url)
				return .handled
			})
	}

	private static func creditText(_ credit: Lyrics.Credit) -> AttributedString {
		func link(_ text: String, _ url: URL) -> AttributedString {
			var part = AttributedString(text)
			part.link = url
			part.underlineStyle = .single
			part.font = DTFont.serif(16).italic()
			return part
		}

		var result = link(credit.text, credit.url)
		if let submitter = credit.submitter {
			result += AttributedString(" · ")
			var by = AttributedString(String(localized: "lyrics-submitted-by \(submitter.name)"))
			if let range = by.range(of: submitter.name) {
				by[range].link = submitter.url
				by[range].underlineStyle = .single
				by[range].font = DTFont.serif(16).italic()
			}
			result += by
		}
		return result
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

	private static func detectLanguage(of lyrics: LyricsLayout) -> Locale.Language? {
		let sample = Self.lines(of: lyrics).prefix(40).map(\.text).joined(separator: "\n")
		guard !sample.isEmpty else { return nil }

		let recognizer = NLLanguageRecognizer()
		recognizer.processString(sample)
		guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.5 else { return nil }
		return Locale.Language(identifier: language.rawValue)
	}

	private static func lines(of lyrics: LyricsLayout) -> [LyricsLayout.Line] {
		lyrics.paragraphs.flatMap(\.lines).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	}

	private func translateButton(_ lyrics: LyricsLayout) -> some View {
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
	private func translateTapped(_ lyrics: LyricsLayout) {
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
	private static func translate(_ lines: [LyricsLayout.Line], from source: Locale.Language, to target: Locale.Language) async -> [String: String] {
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

	/// The line being sung, or else the instrumental break playing.
	private func activeLineId(in lyrics: LyricsLayout) -> String? {
		let currentTime = PlaybackSource.currentTime
		for paragraph in lyrics.paragraphs {
			for line in paragraph.lines {
				if currentTime >= line.startTime && currentTime < line.endTime {
					return line.id
				}
			}
		}
		return self.activeBreak(in: lyrics)?.id
	}

	private func activeBreak(in lyrics: LyricsLayout) -> LyricsLayout.Break? {
		let currentTime = PlaybackSource.currentTime
		return lyrics.paragraphs.lazy.compactMap(\.breakBefore).first { currentTime >= $0.startTime && currentTime < $0.endTime }
	}

	/// The countdown of an instrumental break, as tall as a line of lyrics and placed like one.
	private func breakView(_ pause: LyricsLayout.Break) -> some View {
		let clock = self.clock
		return InstrumentalBreakView(
			startTime: pause.startTime,
			endTime: pause.endTime,
			lyricFont: Self.font(32, useSystemFont: self.useSystemFont),
			isPaused: !PlaybackSource.isPlaying,
			time: { clock.time(at: $0) }
		)
	}

	@ViewBuilder
	private func lineView(_ line: LyricsLayout.Line, synced: Bool) -> some View {
		let currentTime = PlaybackSource.currentTime
		let isBackground = line.isBackground
		let isAlt = line.isAlt
		let isActive = currentTime >= line.startTime && currentTime < line.endTime
		let sizeMultiplier: CGFloat = isBackground ? 0.75 : 1.0

		Button {
			// the end of a hold that opened "Share Lyrics" is not a tap to seek
			if self.heldParagraph {
				self.heldParagraph = false
				return
			}
			// unsynced lyrics have no time to go to
			guard synced else { return }
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
					let words = Self.karaokeWords(line.segments)
					KaraokeText(
						KaraokeText.text(words)
							.font(Self.font(isBackground ? 22 : 32, useSystemFont: self.useSystemFont))
							.foregroundStyle(DTColor.textPrimary),
						clock: self.karaokeClock(for: words, at: currentTime),
						configuration: self.karaokeConfiguration
					)
					.multilineTextAlignment(isAlt ? .trailing : .leading)
					// the line's own animations (scale, dimming) must not interpolate the renderer's clock
					.transaction { $0.animation = nil }
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

	// MARK: - Karaoke

	/// The renderer's settings, from the panel's own styling: words not sung yet are dimmed like a line that
	/// isn't active, and held words glow in the text's color.
	private var karaokeConfiguration: KaraokeConfiguration {
		var configuration = KaraokeConfiguration()
		configuration.inactiveOpacity = 0.4
		configuration.glow.color = DTColor.textPrimary
		configuration.glow.minimumWordDuration = Self.longThreshold
		return configuration
	}

	private static func karaokeWords(_ segments: [LyricsLayout.Segment]) -> [KaraokeWord] {
		segments.map { segment in
			KaraokeWord(
				text: segment.text,
				timing: WordTiming(start: segment.startTime, duration: segment.endTime - segment.startTime),
				endsWord: segment.endsWord
			)
		}
	}

	/// Only a line whose words are moving reads the clock every frame; the others are drawn once, all unlit
	/// before their window and all lit after it.
	private func karaokeClock(for words: [KaraokeWord], at currentTime: TimeInterval) -> KaraokeText.Clock {
		guard let window = KaraokeTiming.animationInterval(for: words.compactMap(\.timing), configuration: self.karaokeConfiguration) else {
			return .fixed(currentTime)
		}
		// `currentTime` is up to one tick behind what the live clock shows
		let margin = LyricsClock.maximumExtrapolation
		if currentTime < window.lowerBound - margin { return .fixed(window.lowerBound - 1) }
		if currentTime > window.upperBound + margin { return .fixed(window.upperBound + 1) }
		let clock = self.clock
		return .live(isPaused: !PlaybackSource.isPlaying, time: { clock.time(at: $0) })
	}
}

/// `PlaybackSource.currentTime` moves in 0.1s ticks (`PlayerEngine`'s time observer, Nafyn Unity's remote clock).
/// The line being sung reads it every frame, carried forward from the last tick while playing so its swipe moves
/// smoothly; capped so a late tick never runs the lyrics ahead of the audio for long. A seek or a pause is just
/// a new tick, so nothing else needs handling.
private final class LyricsClock {
	static let maximumExtrapolation: TimeInterval = 0.25

	private var reported: TimeInterval = .nan
	private var reportedAt = Date.distantPast

	func time(at date: Date) -> TimeInterval {
		let current = PlaybackSource.currentTime
		if current != self.reported {
			self.reported = current
			self.reportedAt = date
		}
		guard PlaybackSource.isPlaying else { return current }
		return current + min(max(0, date.timeIntervalSince(self.reportedAt)), Self.maximumExtrapolation)
	}
}

/// What `LyricsPanel` and `LyricsShareSheet` draw: Braccato's `Lyric[]` (Safyn's `Lyrics.lyrics`) laid out as
/// paragraphs of lines made of timed segments, with every time already moved by the track's lyric offset (so a line
/// is active exactly when `PlaybackSource.currentTime` is inside it, and a tap seeks to the right place).
///
/// - A line's background vocal (its `isBackground` parts) becomes a line of its own under it, without its brackets.
/// - Instrumental gaps are not lines: in synced lyrics, one becomes the `breakBefore` of the paragraph after it, timed
///   up to that paragraph's first line. Syllable-timed lyrics keep one paragraph per line (a TTML `<p>`); line-timed
///   and unsynced ones are grouped into verses, split where a blank or instrumental line was.
struct LyricsLayout: Hashable {
	struct Segment: Hashable, Identifiable {
		let id: String
		var text: String
		let startTime: TimeInterval
		let endTime: TimeInterval
		/// Whether this segment ends a word (vs. being a syllable glued to the next one).
		var endsWord: Bool
	}

	struct Line: Hashable, Identifiable {
		let id: String
		let text: String
		let startTime: TimeInterval
		let endTime: TimeInterval
		let isBackground: Bool
		/// Sung by the alternate voice (an even `ttm:agent` slot): laid out on the trailing side.
		let isAlt: Bool
		let segments: [Segment]
	}

	/// An instrumental gap, from its start to the next lyric.
	struct Break: Hashable, Identifiable {
		let id: String
		let startTime: TimeInterval
		let endTime: TimeInterval
	}

	struct Paragraph: Hashable, Identifiable {
		let id: String
		let lines: [Line]
		/// The instrumental gap just before this paragraph (synced lyrics only).
		var breakBefore: Break? = nil
	}

	let paragraphs: [Paragraph]
	let credit: Lyrics.Credit?
	/// Whether the lines are timed at all (unsynced lyrics are never active and never seek).
	let isSynced: Bool

	init(_ lyrics: Lyrics) {
		self.credit = lyrics.credit
		self.isSynced = lyrics.isSynced
		let offset = lyrics.isSynced ? lyrics.offset : 0
		let onePerLine = lyrics.isRichSynced

		var paragraphs: [Paragraph] = []
		var verse: [Line] = []
		/// Instrumental gap waiting for the paragraph after it (consecutive instrumental lines are one gap), and the
		/// one the current verse starts with.
		var pendingBreak: (id: String, startTime: TimeInterval)?
		var verseBreak: Break?
		func takeBreak(before lines: [Line]) -> Break? {
			defer { pendingBreak = nil }
			guard let pending = pendingBreak, let next = lines.map(\.startTime).min(), next > pending.startTime else { return nil }
			return Break(id: "\(pending.id)-i", startTime: pending.startTime, endTime: next)
		}
		func closeVerse() {
			guard !verse.isEmpty else { return }
			paragraphs.append(Paragraph(id: verse[0].id, lines: verse, breakBefore: verseBreak))
			verse = []
			verseBreak = nil
		}

		for (index, source) in lyrics.lyrics.enumerated() {
			let text = source.mainText
			if source.instrumental || (text.isEmpty && source.backgroundText == nil) {
				closeVerse()
				if source.instrumental, lyrics.isSynced, pendingBreak == nil {
					pendingBreak = ("\(index)", source.startTime + offset)
				}
				continue
			}

			var lines: [Line] = []
			let mainSegments = Self.segments(source.mainParts, id: "\(index)-m", offset: offset)
			if !text.isEmpty {
				lines.append(Line(
					id: "\(index)-m",
					text: text,
					startTime: source.startTime + offset,
					endTime: source.endTime + offset,
					isBackground: false,
					isAlt: source.isAltVoice,
					segments: mainSegments
				))
			}

			if let background = source.backgroundText {
				var segments = Self.segments(source.backgroundParts, id: "\(index)-b", offset: offset)
				// "(yeah)": the brackets say "background", which the smaller line already does
				let unwrapped = Self.unwrap(background)
				if unwrapped != background, !segments.isEmpty {
					if segments[0].text.hasPrefix("(") { segments[0].text.removeFirst() }
					if segments[segments.count - 1].text.hasSuffix(")") { segments[segments.count - 1].text.removeLast() }
					segments.removeAll { $0.text.isEmpty }
				}
				lines.append(Line(
					id: "\(index)-b",
					text: unwrapped,
					startTime: (segments.first?.startTime ?? source.startTime + offset),
					endTime: (segments.last?.endTime ?? source.endTime + offset),
					isBackground: true,
					isAlt: source.isAltVoice,
					segments: segments
				))
			}

			if onePerLine {
				paragraphs.append(Paragraph(id: "\(index)", lines: lines, breakBefore: takeBreak(before: lines)))
			} else {
				if verse.isEmpty { verseBreak = takeBreak(before: lines) }
				verse.append(contentsOf: lines)
			}
		}
		closeVerse()
		self.paragraphs = paragraphs
	}

	/// Timed parts as segments: a part made of spaces only says the word before it ended, and a part's own leading
	/// or trailing space says where a word starts or ends.
	private static func segments(_ parts: [Lyrics.Part], id: String, offset: TimeInterval) -> [Segment] {
		var out: [Segment] = []
		for (index, part) in parts.enumerated() {
			let trimmed = part.words.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.isEmpty {
				if !out.isEmpty { out[out.count - 1].endsWord = true }
				continue
			}
			if part.words.first?.isWhitespace == true, !out.isEmpty {
				out[out.count - 1].endsWord = true
			}
			out.append(Segment(
				id: "\(id)-\(index)",
				text: trimmed,
				startTime: part.startTime + offset,
				endTime: part.endTime + offset,
				endsWord: part.words.last?.isWhitespace == true
			))
		}
		if !out.isEmpty { out[out.count - 1].endsWord = true }
		return out
	}

	private static func unwrap(_ text: String) -> String {
		guard text.count > 1, text.hasPrefix("("), text.hasSuffix(")") else { return text }
		return String(text.dropFirst().dropLast())
	}
}

private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		stride(from: 0, to: self.count, by: size).map { Array(self[$0..<Swift.min($0 + size, self.count)]) }
	}
}
