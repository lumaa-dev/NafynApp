// Made by Lumaa

import SwiftUI
import Safyn

/// Port of the web app's `RequestRow.vue`: cover, title/artist, requester, timestamps, a status pill,
/// and (while active) a live progress readout over `NafynDownloadSocket`. Users with `manageRequests` also
/// get accept (checkmark) / deny (xmark) buttons while the request is waiting.
struct RequestRow: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var observer = RequestProgressObserver()

	var request: NafynRequest

	/// Whether the logged-in user has `manageRequests`; shows the accept/deny buttons on waiting requests.
	var canManage: Bool = false

	/// Called with `.searching` (accept) or `.denied` (deny). The owner performs the server call.
	var onDecision: ((RequestStatus) -> Void)? = nil

	/// Asks the owner to delete this request. Offered only to a manager and never while the pipeline is
	/// working on it, judged on the *live* status (the list's own copy is stale once progress streams in);
	/// the server refuses both cases anyway.
	var onDelete: (() -> Void)? = nil

	/// The logged-in user made this request, or has `manageRequests`: they may cancel it while it hasn't finished.
	var canCancel: Bool = false

	/// Asks the owner to cancel this request (the owner confirms and performs the server call).
	var onCancel: (() -> Void)? = nil

	private var effectiveStatus: RequestStatus {
		self.observer.progress?.stage ?? self.request.status
	}

	private var isLive: Bool {
		switch self.effectiveStatus {
			case .searching, .downloading, .processing:
				true
			case .waiting, .completed, .failed, .denied, .cancelled:
				false
		}
	}

	/// Waiting for a manager or in the pipeline: it can still be cancelled.
	private var isCancellable: Bool {
		self.isLive || self.effectiveStatus == .waiting
	}

	private var requesterName: String {
		switch self.request.requestedBy {
			case .user(let user):
				user.displayName ?? user.username
			case .id(let id):
				id
		}
	}

	/// The requested album's or track's page: an album the user now owns opens its library page, anything
	/// else the MusicBrainz one (which is also where a failed or denied request can be asked for again).
	private var destination: Navigator.Paths {
		switch self.request.type {
			case .album:
				.recentAlbum(id: self.request.musicbrainzId)
			case .track:
				.track(id: self.request.musicbrainzId)
		}
	}

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			CoverImage(url: self.request.info?.coverArt.flatMap { URL(string: $0) })
				.frame(width: 56, height: 56)

			VStack(alignment: .leading, spacing: 6) {
				HStack(alignment: .top) {
					VStack(alignment: .leading, spacing: 2) {
						Text(self.request.info?.title ?? self.request.musicbrainzId)
							.font(DTFont.serif(19))
							.foregroundStyle(DTColor.textPrimary)
							.lineLimit(1)

						if let artist = self.request.info?.artist.name {
							Text(artist)
								.font(DTFont.serif(16))
								.foregroundStyle(DTColor.textPrimary.opacity(0.6))
								.lineLimit(1)
						}
					}

					Spacer()

					VStack(alignment: .trailing, spacing: 6) {
						self.statusPill

						if self.canManage, self.effectiveStatus == .waiting, let onDecision {
							self.decisionButtons(onDecision)
						}
					}
				}

				HStack(spacing: 4) {
					Text(self.requesterName)
					Text("•")
					Text(self.request.createdAt.formatted(date: .abbreviated, time: .shortened))
				}
				.font(DTFont.system(15))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

				if self.isLive {
					self.progressSection
				}
			}
		}
		.padding(.vertical, 4)
		// open what was requested; the accept / deny buttons keep their own taps
		.contentShape(Rectangle())
		.onTapGesture {
			Navigator.shared.send(to: self.destination)
		}
		.accessibilityAddTraits(.isButton)
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			if self.canCancel, self.isCancellable, let onCancel {
				Button {
					onCancel()
				} label: {
					Label(String(localized: "cancel"), systemImage: "stop.circle")
				}
				.tint(DTColor.statusWaiting)
				.disabled(NetworkMonitor.shared.isOffline)
			}
			if self.canManage, !self.isLive, let onDelete {
				Button(role: .destructive) {
					onDelete()
				} label: {
					Label(String(localized: "delete"), systemImage: "trash")
				}
				.tint(DTColor.dangerText)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
		.task(id: self.request.id) {
			// denied is as terminal as completed/failed: nothing will ever stream for it
			guard let server, self.request.status != .denied, self.request.status != .completed, self.request.status != .failed, self.request.status != .cancelled else { return }
			self.observer.connect(server: server, requestId: self.request.id)
		}
		.onDisappear {
			self.observer.disconnect()
		}
	}

	private func decisionButtons(_ onDecision: @escaping (RequestStatus) -> Void) -> some View {
		HStack(spacing: 8) {
			Button {
				onDecision(.searching)
			} label: {
				Image(systemName: "checkmark")
			}
			.tint(DTColor.statusSuccess)
			.accessibilityLabel(String(localized: "accept-request"))

			Button {
				onDecision(.denied)
			} label: {
				Image(systemName: "xmark")
			}
			.tint(DTColor.dangerText)
			.accessibilityLabel(String(localized: "deny-request"))
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.circle)
		.controlSize(.small)
		.disabled(NetworkMonitor.shared.isOffline)
	}

	@ViewBuilder
	private var statusPill: some View {
		let style = self.statusStyle
		Text(style.label)
			.font(DTFont.system(14, weight: .semibold))
			.padding(.horizontal, 8)
			.padding(.vertical, 3)
			.foregroundStyle(style.filled ? Color.black.opacity(0.8) : style.color)
			.background {
				if style.filled {
					Capsule().fill(style.color)
				} else {
					Capsule().strokeBorder(style.color, lineWidth: 1)
				}
			}
	}

	private var statusStyle: (color: Color, filled: Bool, label: String) {
		return switch self.effectiveStatus {
			case .denied:
				(DTColor.statusFailure, false, String(localized: "status-denied"))
			case .cancelled:
				(DTColor.statusFailure, false, String(localized: "status-cancelled"))
			case .waiting:
				(DTColor.statusWaiting, false, String(localized: "status-waiting"))
			case .searching:
				(DTColor.statusActive, true, String(localized: "status-searching"))
			case .downloading:
				(DTColor.statusActive, true, String(localized: "status-downloading"))
			case .processing:
				(DTColor.statusActive, true, String(localized: "status-processing"))
			case .completed:
				(DTColor.statusSuccess, true, String(localized: "status-completed"))
			case .failed:
				(DTColor.statusFailure, true, String(localized: "status-failed"))
		}
	}

	@ViewBuilder
	private var progressSection: some View {
		if let progress = self.observer.progress {
			VStack(alignment: .leading, spacing: 4) {
				if let downloaded = progress.bytesDownloaded, let total = progress.totalBytes, total > 0 {
					ProgressView(value: Double(downloaded), total: Double(total))
						.tint(DTColor.statusActive)
				} else {
					ProgressView()
						.tint(DTColor.statusActive)
				}

				HStack(spacing: 6) {
					if let trackIndex = progress.trackIndex, let trackCount = progress.trackCount {
						Text("track-progress \(trackIndex) \(trackCount)")
					}
					if let speed = progress.speedBytesPerSec {
						Text("\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
					}
					if let eta = progress.etaSeconds ?? nil, let formatted = Self.durationFormatter.string(from: eta) {
						Text(formatted)
					}
				}
				.font(DTFont.system(14))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

				if let message = progress.message {
					Text(message)
						.font(DTFont.system(14))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						.lineLimit(1)
				}
			}
		}
	}

	private static let durationFormatter: DateComponentsFormatter = {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.minute, .second]
		formatter.unitsStyle = .abbreviated
		return formatter
	}()
}
