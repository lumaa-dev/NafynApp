// Made by Lumaa

import Foundation
import Safyn

/// What the person did with a Discover card, reported back to the server's bandit
/// (`Recommendations.feedback`). Mirrors the web client's `useRecFeedback`.
///
/// Opening a card starts an attribution: for the next 30 minutes (the server's window), what is played,
/// previewed or requested from what the card leads to counts for that card's (decision, slot):
/// - a mix: its tracks and suggestions (filled in by ``MixDetailView`` once loaded)
/// - a suggestion: that recording's preview and request
/// - an album / playlist: playback started within 10 minutes of opening it
///
/// Listens are measured here, not by `PlayTracker`, because this works whether or not the listening history
/// is on (a recommendation's reward is not a play event).
@MainActor
final class RecommendationFeedback {
	static let shared = RecommendationFeedback()

	private struct Attribution {
		let decisionId: String
		let slot: Int
		let ref: String
		let openedAt: Date
		/// Media IDs whose listens count; `nil` = anything started soon after opening.
		var trackIds: Set<String>?
		var recordingIds: Set<String>
		let server: NafynServer
	}

	private static let window: TimeInterval = 30 * 60
	private static let openPlayWindow: TimeInterval = 10 * 60
	private var attributions: [Attribution] = []

	private var listen: (trackId: String, startedAt: Date, accumulated: TimeInterval, resumedAt: Date?)? = nil
	private var preview: (id: String, since: Date)? = nil

	private init() {}

	private var live: [Attribution] {
		self.attributions.removeAll { Date.now.timeIntervalSince($0.openedAt) >= Self.window }
		return self.attributions
	}

	private func send(_ attribution: Attribution, _ event: RecommendationFeedbackEvent, ms: Int = 0) {
		let endpoint = Recommendations.feedback(decisionId: attribution.decisionId, slot: attribution.slot, event: event, msPlayed: ms)
		let server = attribution.server
		// background traffic the person did not ask for: never a toast
		Task { _ = try? await server.send(endpoint) as RecommendationFeedbackResponse }
	}

	// MARK: - Cards

	func cardOpened(decisionId: String, slot: Int, item: RecommendationItem, server: NafynServer?) {
		guard let server else { return }
		let ref = "\(item.kind.rawValue):\(item.refId)"
		if let existing = self.live.first(where: { $0.decisionId == decisionId && $0.slot == slot }) {
			self.send(existing, .open)
			return
		}
		let attribution = Attribution(
			decisionId: decisionId,
			slot: slot,
			ref: ref,
			openedAt: .now,
			trackIds: item.kind == .mix || item.kind == .suggestion ? [] : nil,
			recordingIds: item.kind == .suggestion ? [item.refId.lowercased()] : [],
			server: server
		)
		self.attributions = Array(([attribution] + self.live).prefix(8))
		self.send(attribution, .open)
	}

	/// The mix screen, once loaded: which tracks and suggestions belong to the card that led there.
	func attributeMix(id: String, mediaIds: [String], recordingIds: [String]) {
		for index in self.attributions.indices where self.attributions[index].ref == "mix:\(id)" {
			self.attributions[index].trackIds = Set(mediaIds)
			self.attributions[index].recordingIds = Set(recordingIds.map { $0.lowercased() })
		}
	}

	// MARK: - Listens (driven by `PlayTracker`)

	func listenBegan(trackId: String) {
		self.listenEnded()
		self.listen = (trackId, .now, 0, .now)
	}

	func listenPaused() {
		guard var listen, let resumedAt = listen.resumedAt else { return }
		listen.accumulated += Date.now.timeIntervalSince(resumedAt)
		listen.resumedAt = nil
		self.listen = listen
	}

	func listenResumed() {
		guard var listen, listen.resumedAt == nil else { return }
		listen.resumedAt = .now
		self.listen = listen
	}

	func listenEnded() {
		guard let listen else { return }
		self.listen = nil
		let heard = listen.accumulated + (listen.resumedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
		guard heard > 0 else { return }
		for attribution in self.live {
			let matches: Bool
			if let ids = attribution.trackIds {
				matches = ids.contains(listen.trackId)
			} else {
				let sinceOpen = listen.startedAt.timeIntervalSince(attribution.openedAt)
				matches = sinceOpen >= 0 && sinceOpen < Self.openPlayWindow
			}
			if matches { self.send(attribution, .play, ms: Int(heard * 1000)) }
		}
	}

	// MARK: - Previews and requests

	func previewStarted(id: String) {
		self.previewStopped()
		self.preview = (id, .now)
	}

	func previewStopped() {
		guard let preview else { return }
		self.preview = nil
		let ms = Int(Date.now.timeIntervalSince(preview.since) * 1000)
		for attribution in self.live where attribution.recordingIds.contains(preview.id.lowercased()) {
			self.send(attribution, .preview, ms: ms)
		}
	}

	func requested(recordingId: String) {
		for attribution in self.live where attribution.recordingIds.contains(recordingId.lowercased()) {
			self.send(attribution, .request)
		}
	}
}
