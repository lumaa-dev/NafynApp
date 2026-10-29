// Made by Lumaa

import SwiftUI

/// Manage offline downloads: every locally-downloaded track, grouped by album, with its storage
/// footprint, swipe-to-delete, and a "delete all" escape hatch. Lives on its own pushed screen (see
/// `Navigator.Paths.settingsDownloads`) rather than inline in `SettingsView`, since the list can get long.
struct DownloadsSettingsSection: View {
	@State private var showingDeleteAllConfirmation = false

	var body: some View {
		Group {
			Section {
				HStack {
					Text(String(localized: "downloads-total-size"))
					Spacer()
					Text(Self.formattedSize(DownloadManager.shared.totalBytes))
						.foregroundStyle(DTColor.textPrimary.opacity(0.55))
				}

				if !DownloadManager.shared.downloads.isEmpty {
					Button(role: .destructive) {
						self.showingDeleteAllConfirmation = true
					} label: {
						Label(String(localized: "downloads-delete-all"), systemImage: "trash")
							.foregroundStyle(DTColor.buttonDanger)
					}
					.tint(DTColor.buttonDanger)
				}
			}

			Section {
				if DownloadManager.shared.downloads.isEmpty {
					Text(String(localized: "downloads-empty"))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				} else {
					ForEach(DownloadManager.shared.downloads, id: \.id) { track in
						HStack(spacing: 12) {
							CoverImage(url: track.coverArt.flatMap { URL(string: $0) })
								.frame(width: 40, height: 40)

							VStack(alignment: .leading, spacing: 2) {
								Text(track.title)
									.foregroundStyle(DTColor.textPrimary)
									.lineLimit(1)
								
								Text(track.artistName)
									.font(.footnote)
									.foregroundStyle(DTColor.textPrimary.opacity(0.55))
									.lineLimit(1)
							}

							Spacer()

							Text(Self.formattedSize(track.fileSize))
								.font(.footnote)
								.foregroundStyle(DTColor.textPrimary.opacity(0.45))
						}
						.swipeActions {
							Button(role: .destructive) {
								DownloadManager.shared.delete(track)
							} label: {
								Label(String(localized: "delete"), systemImage: "trash")
							}
							.tint(DTColor.buttonDanger)
						}
					}
				}
			}
		}
		.alert(String(localized: "downloads-delete-all-confirm"), isPresented: self.$showingDeleteAllConfirmation) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				DownloadManager.shared.deleteAll()
			}
		}
	}

	private func play(_ track: DownloadedTrack, in group: [DownloadedTrack]) {
		PlaybackSource.play(track.mediaRow, queue: group.map(\.mediaRow))
	}

	private static func formattedSize(_ bytes: Int64) -> String {
		ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
	}
}
