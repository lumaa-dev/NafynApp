// Made by Lumaa

import SwiftUI
import Safyn

/// Listening-history controls: the opt-in toggle, a full data export, and an irreversible wipe.
///
/// Listening history is opt-in server-side (`historyEnabled` is `false` for anyone who has never
/// touched it), so nothing is recorded until the user turns this on here.
struct InsightsSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var settings: InsightsSettings? = nil
	@State private var isUpdating = false
	@State private var isExporting = false
	@State private var exportURL: URL? = nil
	@State private var showingDeleteConfirmation = false
	@State private var isDeleting = false
	@State private var toast = ToastState()

	private var historyBinding: Binding<Bool> {
		Binding(
			get: { self.settings?.historyEnabled ?? false },
			set: { self.setHistoryEnabled($0) }
		)
	}

	var body: some View {
		Section {
			Toggle(String(localized: "listening-history"), isOn: self.historyBinding)
				.disabled(self.settings == nil || self.isUpdating || NetworkMonitor.shared.isOffline)

			if let exportURL {
				ShareLink(item: exportURL) {
					Label(String(localized: "insights-export"), systemImage: "square.and.arrow.up")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)
			} else {
				Button {
					self.exportHistory()
				} label: {
					HStack {
						Label(String(localized: "insights-export"), systemImage: "arrow.down.document")
							.foregroundStyle(Color.primary)

						if self.isExporting {
							Spacer()
							ProgressView()
								.tint(DTColor.textPrimary)
						}
					}
				}
				.tint(Color.primary)
				.disabled(self.isExporting || NetworkMonitor.shared.isOffline)
			}

			Button(role: .destructive) {
				self.showingDeleteConfirmation = true
			} label: {
				Label(String(localized: "insights-delete-history"), systemImage: "trash")
					.foregroundStyle(DTColor.dangerText)
			}
			.tint(DTColor.dangerText)
			.disabled(self.isDeleting || NetworkMonitor.shared.isOffline)
		}
		header: {
			Text(String(localized: "insights"))
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(String(localized: "listening-history-footer"))
				Text(String(localized: "insights-delete-history-footer"))
			}
		}
		.toast(self.toast)
		.alert(String(localized: "insights-delete-history"), isPresented: self.$showingDeleteConfirmation) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.deleteHistory()
			}
		} message: {
			Text(String(localized: "insights-delete-history-confirm"))
		}
		.task {
			self.settings = await PlayTracker.shared.refreshSettings()
		}
	}

	private func setHistoryEnabled(_ enabled: Bool) {
		self.isUpdating = true

		Task {
			do {
				self.settings = try await PlayTracker.shared.setHistoryEnabled(enabled)
			} catch {
				self.toast.failure(error)
			}
			self.isUpdating = false
		}
	}

	/// Writes the export to a temporary file so it can be shared as a real `.json` document — the share
	/// sheet can't offer "Save to Files" for an in-memory `Data` without one.
	private func exportHistory() {
		guard let server else { return }
		self.isExporting = true

		Task {
			do {
				let data = try await server.insightsExport()
				let url = FileManager.default.temporaryDirectory
					.appendingPathComponent("nafyn-listening-history.json")
				try data.write(to: url, options: .atomic)
				self.exportURL = url
			} catch {
				self.toast.failure(error)
			}
			self.isExporting = false
		}
	}

	private func deleteHistory() {
		guard let server else { return }
		self.isDeleting = true

		Task {
			do {
				let response: DeletedResponse = try await server.send(Insights.deleteHistory)
				if response.deleted {
					PlayTracker.shared.discardPending()
					self.exportURL = nil
					self.toast.success(String(localized: "insights-history-deleted"))
				}
			} catch {
				self.toast.failure(error)
			}
			self.isDeleting = false
		}
	}
}
