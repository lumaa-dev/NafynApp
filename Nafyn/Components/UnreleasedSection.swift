// Made by Lumaa

import SwiftUI
import Safyn

/// What an album/track screen shows instead of "Request" while the media isn't out yet: a countdown (or
/// "Expected …" when MusicBrainz only knows the month/year) and a Notify me / Following toggle.
struct UnreleasedSection: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.coverPalette) private var palette

	let mbid: String
	let kind: ReleaseSubscriptionKind
	let releaseDate: Date?
	let precision: ReleaseDatePrecision?
	let toast: ToastState

	/// Called when the countdown reaches zero, so the screen can reload and offer Request instead.
	let onReleased: () -> Void

	@State private var isFollowing: Bool
	@State private var isUpdating = false

	init(mbid: String, kind: ReleaseSubscriptionKind, releaseDate: Date?, precision: ReleaseDatePrecision?, subscribed: Bool, toast: ToastState, onReleased: @escaping () -> Void) {
		self.mbid = mbid
		self.kind = kind
		self.releaseDate = releaseDate
		self.precision = precision
		self.toast = toast
		self.onReleased = onReleased
		self._isFollowing = State(initialValue: subscribed)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			self.timing

			// no announced date means the server refuses to follow it (409)
			if self.releaseDate != nil {
				self.followButton
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var timing: some View {
		if let releaseDate {
			if self.precision == nil || self.precision == .day {
				VStack(alignment: .leading, spacing: 2) {
					Text("out-in")
						.font(DTFont.system(14, weight: .semibold))
						.foregroundStyle(self.palette?.secondary ?? DTColor.textPrimary.opacity(0.5))

					ReleaseCountdown(releaseDate: releaseDate, onReleased: self.onReleased)
						.font(DTFont.serif(22))
						.foregroundStyle(self.palette?.primary ?? DTColor.textPrimary)
				}
			} else {
				// a partial date is padded to its first day server-side, so counting down to it would lie
				Text("expected \(self.partialDateText(releaseDate))")
					.font(DTFont.serif(22))
					.foregroundStyle(self.palette?.primary ?? DTColor.textPrimary)
			}
		} else {
			Text("release-date-unknown")
				.font(DTFont.system(16))
				.foregroundStyle(self.palette?.secondary ?? DTColor.textPrimary.opacity(0.5))
		}
	}

	@ViewBuilder
	private var followButton: some View {
		if self.isFollowing {
			Button {
				self.setFollowing(false)
			} label: {
				Text("following")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
			.disabled(self.isUpdating || NetworkMonitor.shared.isOffline)
		} else {
			Button {
				self.setFollowing(true)
			} label: {
				Text("notify-me")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())
			.disabled(self.isUpdating || NetworkMonitor.shared.isOffline)
		}
	}

	/// "November 2027" / "2027", read in UTC because the API's date is UTC midnight.
	private func partialDateText(_ date: Date) -> String {
		var style = Date.FormatStyle(timeZone: .gmt)
		switch self.precision {
			case .month: style = style.month(.wide).year()
			default: style = style.year()
		}
		return date.formatted(style)
	}

	private func setFollowing(_ follow: Bool) {
		guard let server, !self.isUpdating else { return }
		self.isUpdating = true

		Task {
			defer { self.isUpdating = false }
			do {
				if follow {
					// ask the first time it matters, not at launch
					await PushManager.shared.requestAuthorizationIfNeeded()
				}
				self.isFollowing = try await server.setFollowing(follow, mbid: self.mbid, type: self.kind)
				self.toast.success(follow ? String(localized: "follow-confirmation") : String(localized: "unfollow-confirmation"))
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

extension NafynError {
	/// Whether this is the server's refusal to request media that isn't out yet (`403 Not released yet`).
	var isNotReleasedYet: Bool {
		if case .server(let statusCode, let error) = self {
			return statusCode == 403 && "\(error.statusMessage) \(error.message ?? String())".localizedCaseInsensitiveContains("not released")
		}
		return false
	}
}
