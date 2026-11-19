// Made by Lumaa

import Foundation
import Safyn
#if canImport(UIKit)
import UIKit
#endif

/// Collects play events for the Insights ("Your Music Year") pipeline and flushes them to
/// `Insights.ingestEvents`.
///
/// Mirrors the web client's tracker: one open session per played track, accumulating only wall-clock
/// milliseconds actually heard (paused time excluded), flushed in batches. Every event carries a
/// client-minted `eventId`, and ingestion is idempotent server-side, so a batch that fails mid-flight is
/// simply retried on the next flush without double-counting.
///
/// Nothing is recorded while the user's Listening History setting is off — the server discards such
/// batches anyway, but not sending them at all keeps a disabled account from queuing events on disk.
@Observable
@MainActor
final class PlayTracker {
	static let shared = PlayTracker()

	/// The user's listening-history preferences, once loaded from the server.
	private(set) var settings: InsightsSettings? = nil

	/// Whether events are being recorded. `false` until the settings load, so a slow/failed settings
	/// fetch fails closed rather than queueing events the user may have opted out of.
	var historyEnabled: Bool {
		self.settings?.historyEnabled ?? false
	}

	/// Plays are scrobbled to ListenBrainz (server side, from these same events), so they are reported even with the
	/// listening history off - the server then scrobbles them and stores nothing.
	private(set) var scrobbling = false

	/// Whether finished plays are queued and sent: the history or ListenBrainz wants them.
	var capturesPlays: Bool {
		self.historyEnabled || self.scrobbling
	}

	/// Settings → ListenBrainz changed the connection.
	func setScrobbling(_ scrobbling: Bool) {
		self.scrobbling = scrobbling
	}

	/// Plays shorter than this are dropped rather than sent — a skip isn't a listen.
	private static let minimumPlayedMs: Int = 5_000

	/// The server takes 50 events per request (`MAX_BATCH_SIZE`); a longer offline queue is sent in several.
	private static let maximumBatchSize: Int = 50

	private static let pendingDefaultsKey = "insights.pendingEvents"

	/// The play still open when the app went to the background, kept on disk in case the app is killed there.
	private static let openSessionDefaultsKey = "insights.openSession"

	/// One in-progress play. `accumulatedMs` grows only while playback is actually running, so pausing
	/// a track for an hour doesn't turn into an hour of listening.
	private struct Session {
		let eventId: String
		let trackId: String
		let playlistId: String?
		let source: PlayEventSource
		let startedAt: Int64
		var accumulatedMs: Int
		var resumedAt: Date?

		/// Total milliseconds heard so far, including the currently running stretch.
		func playedMs(now: Date = .now) -> Int {
			guard let resumedAt else { return self.accumulatedMs }
			return self.accumulatedMs + Int(now.timeIntervalSince(resumedAt) * 1000)
		}
	}

	private weak var server: NafynServer?
	private var session: Session? {
		didSet {
			// the play is over (queued, dropped or discarded): its on-disk snapshot must not be recovered later
			if self.session == nil {
				Self.saveOpenSession(nil)
			}
		}
	}
	private var pending: [StoredPlayEvent]
	private var isFlushing = false

	/// A play was queued while a flush was already in flight; it goes out as soon as that flush ends.
	private var flushAgain = false

	private init() {
		self.pending = Self.loadPending()

		// The app was killed in the background while a play was open: that play ends here, with what was heard.
		if let orphan = Self.loadOpenSession() {
			Self.saveOpenSession(nil)
			if orphan.durationMs >= Self.minimumPlayedMs {
				self.pending.append(orphan)
				Self.savePending(self.pending)
			}
		}

		#if canImport(UIKit)
		NotificationCenter.default.addObserver(
			forName: UIApplication.didEnterBackgroundNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				// The open session is only snapshotted to disk, never closed: audio keeps playing in the
				// background, and closing it here cut the track's play at the moment of locking the phone
				// (too short for the half-the-track scrobbling rule) and left the rest of it unrecorded.
				self.checkpointSession()
				Task { await self.flush() }
			}
		}

		// Plays finished in the background (a looped track on a locked phone) wait in the queue: send them as
		// soon as the person is back instead of at the next threshold.
		NotificationCenter.default.addObserver(
			forName: UIApplication.willEnterForegroundNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				Task { await self.flush() }
			}
		}
		#endif
	}

	// MARK: - Configuration

	/// Binds the tracker to the logged-in server and loads the user's listening-history settings.
	///
	/// Called from `RootView.onAppear` alongside `PlayerEngine.configure(server:)`.
	func configure(server: NafynServer) {
		self.server = server

		Task {
			await self.refreshSettings()
			await self.flush()
		}
	}

	/// Re-reads the listening-history settings from the server.
	@discardableResult
	func refreshSettings() async -> InsightsSettings? {
		guard let server else { return nil }

		let settings: InsightsSettings? = try? await server.send(Insights.settings)
		if let settings {
			self.settings = settings
			self.scrobbling = settings.scrobbling ?? false
			await self.syncTimeZoneIfNeeded(settings)
		}
		return settings
	}

	/// Turns listening history on or off, and reports the settings the server ended up with.
	@discardableResult
	func setHistoryEnabled(_ enabled: Bool) async throws -> InsightsSettings {
		guard let server else { throw NafynError.unauthenticated }

		let updated: InsightsSettings = try await server.send(
			Insights.updateSettings(historyEnabled: enabled, tzOffsetMinutes: Self.localOffsetMinutes)
		)
		self.settings = updated

		if !enabled, !self.scrobbling {
			// Nothing already queued is worth keeping: the server would discard it, and holding it would
			// silently ship the user's opted-out listening the next time they switch the setting back on.
			self.session = nil
			self.pending = []
			Self.savePending([])
		}
		return updated
	}

	/// Drops every locally queued event, for after a server-side history wipe.
	func discardPending() {
		self.session = nil
		self.pending = []
		Self.savePending([])
	}

	/// The device's current UTC offset in minutes, clamped to the range the API accepts.
	private static var localOffsetMinutes: Int {
		let minutes = TimeZone.current.secondsFromGMT() / 60
		return min(max(minutes, -720), 840)
	}

	/// Pushes the device's time-zone offset up when it no longer matches the stored one — day, week, and
	/// year boundaries are computed server-side from this, so a stale offset silently misfiles plays.
	private func syncTimeZoneIfNeeded(_ settings: InsightsSettings) async {
		guard settings.historyEnabled, settings.tzOffsetMinutes != Self.localOffsetMinutes else { return }
		guard let server else { return }

		let updated: InsightsSettings? = try? await server.send(
			Insights.updateSettings(historyEnabled: nil, tzOffsetMinutes: Self.localOffsetMinutes)
		)
		if let updated {
			self.settings = updated
		}
	}

	// MARK: - Session lifecycle (driven by `PlayerEngine`)

	/// Opens a session for a freshly started track, closing any session still open for the previous one.
	func began(track: MediaRow, source: PlayEventSource, playlistId: String?) {
		self.finished(completed: false)
		// a listen that came from a Discover card is that card's reward, history on or off
		RecommendationFeedback.shared.listenBegan(trackId: track.id)
		if self.scrobbling, let server {
			// ListenBrainz' "playing now"; the listen itself comes from this play's event
			let mediaId = track.id
			Task { _ = try? await server.sendRaw(User.listenBrainzNowPlaying(mediaId: mediaId)) }
		}
		guard self.capturesPlays else { return }

		self.session = Session(
			eventId: UUID().uuidString,
			trackId: track.id,
			playlistId: playlistId,
			source: source,
			startedAt: Int64(Date.now.timeIntervalSince1970 * 1000),
			accumulatedMs: 0,
			resumedAt: .now
		)
	}

	/// Stops accumulating listened time (playback paused).
	func paused() {
		RecommendationFeedback.shared.listenPaused()
		guard var session = self.session, session.resumedAt != nil else { return }
		session.accumulatedMs = session.playedMs()
		session.resumedAt = nil
		self.session = session
	}

	/// Resumes accumulating listened time (playback resumed).
	func resumed() {
		RecommendationFeedback.shared.listenResumed()
		guard var session = self.session, session.resumedAt == nil else { return }
		session.resumedAt = .now
		self.session = session
	}

	/// Closes the open session, queueing it as an event if enough of the track was actually heard.
	func finished(completed: Bool) {
		RecommendationFeedback.shared.listenEnded()
		guard let session = self.session else { return }
		self.session = nil

		guard self.capturesPlays, session.playedMs() >= Self.minimumPlayedMs else { return }

		self.pending.append(Self.event(for: session, completed: completed))
		Self.savePending(self.pending)

		// Every finished play goes out right away: a looped track (Repeat One) finishes one every few minutes, and
		// holding them back until `flushThreshold` left the server (stats and the ListenBrainz scrobbles) behind for as
		// long as the app stayed in the background. The batch is still sent in one request when several are waiting.
		Task { await self.flush() }
	}

	/// Writes the open session to disk without closing it, before the app is suspended.
	///
	/// A backgrounded app may be killed without ever running more code, so a session held only in memory
	/// would be lost. It is not queued here though: the server scrobbles and records an event once (its id
	/// is ignored the second time), so a play must be sent when it is over, with everything that was heard.
	/// The snapshot is picked up by `init` only if the app dies before that.
	private func checkpointSession() {
		guard let session, self.capturesPlays else { return }
		Self.saveOpenSession(Self.event(for: session, completed: false))
	}

	private static func event(for session: Session, completed: Bool) -> StoredPlayEvent {
		StoredPlayEvent(
			eventId: session.eventId,
			trackId: session.trackId,
			playlistId: session.playlistId,
			startedAt: session.startedAt,
			durationMs: min(session.playedMs(), 86_400_000),
			completed: completed,
			source: session.source
		)
	}

	// MARK: - Flushing

	/// Sends every queued event, clearing them once the server has accepted the batch.
	func flush() async {
		guard let server else { return }
		guard !self.isFlushing else {
			self.flushAgain = true
			return
		}

		let batch = Array(self.pending.prefix(Self.maximumBatchSize))
		guard !batch.isEmpty else { return }

		self.isFlushing = true
		defer {
			self.isFlushing = false
			// A play finished while this request was in flight, and it would otherwise wait for the next trigger.
			if self.flushAgain, !self.pending.isEmpty {
				self.flushAgain = false
				Task { await self.flush() }
			}
		}

		do {
			let response: IngestPlayEventsResponse = try await server.send(
				Insights.ingestEvents(events: batch.map(\.input))
			)

			// Only drop the events actually sent — anything queued while the request was in flight
			// stays for the next flush.
			let sentIds = Set(batch.map(\.eventId))
			self.pending.removeAll { sentIds.contains($0.eventId) }
			Self.savePending(self.pending)
			if !self.pending.isEmpty { self.flushAgain = true }

			self.scrobbling = response.scrobbling ?? false
			if !response.historyEnabled, self.settings?.historyEnabled == true {
				self.settings = InsightsSettings(
					historyEnabled: false,
					enabledAt: self.settings?.enabledAt,
					disabledAt: self.settings?.disabledAt,
					tzOffsetMinutes: self.settings?.tzOffsetMinutes ?? Self.localOffsetMinutes,
					scrobbling: response.scrobbling
				)
			}
			if !response.wantsEvents {
				// The setting was switched off elsewhere; stop queueing until it's read again.
				self.settings = InsightsSettings(
					historyEnabled: false,
					enabledAt: self.settings?.enabledAt,
					disabledAt: self.settings?.disabledAt,
					tzOffsetMinutes: self.settings?.tzOffsetMinutes ?? Self.localOffsetMinutes
				)
				self.session = nil
				self.pending = []
				Self.savePending([])
			}
		} catch {
			// Kept on disk; ingestion is idempotent, so the next flush safely retries this same batch.
		}
	}

	// MARK: - Local persistence

	private static func loadPending() -> [StoredPlayEvent] {
		guard let data = UserDefaults.standard.data(forKey: Self.pendingDefaultsKey) else { return [] }
		return (try? JSONDecoder().decode([StoredPlayEvent].self, from: data)) ?? []
	}

	private static func savePending(_ events: [StoredPlayEvent]) {
		guard let data = try? JSONEncoder().encode(events) else { return }
		UserDefaults.standard.set(data, forKey: Self.pendingDefaultsKey)
	}

	private static func loadOpenSession() -> StoredPlayEvent? {
		guard let data = UserDefaults.standard.data(forKey: Self.openSessionDefaultsKey) else { return nil }
		return try? JSONDecoder().decode(StoredPlayEvent.self, from: data)
	}

	private static func saveOpenSession(_ event: StoredPlayEvent?) {
		guard let event, let data = try? JSONEncoder().encode(event) else {
			UserDefaults.standard.removeObject(forKey: Self.openSessionDefaultsKey)
			return
		}
		UserDefaults.standard.set(data, forKey: Self.openSessionDefaultsKey)
	}
}

/// A queued play event, mirroring Safyn's `PlayEventInput`.
///
/// The Safyn type is `Encodable` only, so it can't itself round-trip through the on-disk queue that
/// keeps events across app launches — this mirror is `Codable` and rebuilds the real type on flush.
private struct StoredPlayEvent: Codable, Hashable {
	let eventId: String
	let trackId: String
	let playlistId: String?
	let startedAt: Int64
	let durationMs: Int
	let completed: Bool
	let source: PlayEventSource

	var input: PlayEventInput {
		PlayEventInput(
			eventId: self.eventId,
			trackId: self.trackId,
			playlistId: self.playlistId,
			startedAt: self.startedAt,
			durationMs: self.durationMs,
			completed: self.completed,
			source: self.source
		)
	}
}
