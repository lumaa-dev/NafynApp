// Made by Lumaa

import SwiftUI
import Safyn

/// Port of the web app's `RequestRow.vue`: cover, title/artist, requester, timestamps, a status pill,
/// and (while active) a live progress readout over `NafynDownloadSocket`. No action buttons — mirrors
/// the web app exactly, which has none either.
struct RequestRow: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var observer = RequestProgressObserver()

	var request: NafynRequest

	private var effectiveStatus: RequestStatus {
		self.observer.progress?.stage ?? self.request.status
	}

	private var isLive: Bool {
		switch self.effectiveStatus {
			case .searching, .downloading, .processing:
				true
			case .waiting, .completed, .failed:
				false
		}
	}

	private var requesterName: String {
		switch self.request.requestedBy {
			case .user(let user):
				user.displayName ?? user.username
			case .id(let id):
				id
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

					self.statusPill
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
		.task(id: self.request.id) {
			guard let server, self.request.status != .completed, self.request.status != .failed else { return }
			self.observer.connect(server: server, requestId: self.request.id)
		}
		.onDisappear {
			self.observer.disconnect()
		}
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
		switch self.effectiveStatus {
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
