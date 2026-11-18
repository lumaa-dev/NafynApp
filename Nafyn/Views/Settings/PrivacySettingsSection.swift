// Made by Lumaa

import SwiftUI
import Safyn

struct PrivacySettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var sessions: [SessionSummary] = []
	@State private var isLoaded = false
	@State private var isExporting = false
	@State private var exportedFileURL: URL? = nil
	@State private var toast = ToastState()
	/// Personalized recommendations (mixes, Discover); `nil` until loaded, or when the server has them off.
	@State private var recommendations: RecommendationSettings? = nil
	@State private var savingRecommendations = false

	var body: some View {
		Group {
			// GDPR art. 21: objecting to the profiling behind mixes and Discover stops it and deletes what it built
			if let recommendations, recommendations.available {
				Section {
					Toggle(String(localized: "recommendations-toggle"), isOn: Binding(
						get: { recommendations.enabled },
						set: { self.setRecommendations($0) }
					))
					.disabled(self.savingRecommendations || NetworkMonitor.shared.isOffline)
				}
				header: {
					Text(String(localized: "recommendations"))
				} footer: {
					Text(String(localized: "recommendations-footer"))
				}
			}

			Section {
				ForEach(self.sessions) { session in
					HStack(spacing: 12) {
						Image(systemName: session.isCurrent ? "checkmark.circle.fill" : "iphone")
							.foregroundStyle(session.isCurrent ? DTColor.statusSuccess : DTColor.textPrimary.opacity(0.55))

						VStack(alignment: .leading, spacing: 2) {
							Text(session.deviceLabel)
								.foregroundStyle(DTColor.textPrimary)
							Text(session.createdAtDate, style: .date)
								.font(DTFont.text(.footnote))
								.foregroundStyle(DTColor.textPrimary.opacity(0.55))
						}
					}
					.swipeActions {
						if !session.isCurrent {
							Button(role: .destructive) {
								self.revoke(session)
							} label: {
								Label(String(localized: "delete"), systemImage: "trash")
							}
							.tint(DTColor.dangerText)
							.disabled(NetworkMonitor.shared.isOffline)
						}
					}
				}
			}
			header: {
				Text(String(localized: "sessions"))
			} footer: {
				Text(String(localized: "sessions-footer"))
			}

			Section {
				if let exportedFileURL {
					ShareLink(item: exportedFileURL) {
						Label(String(localized: "export-account-data-share"), systemImage: "square.and.arrow.up")
					}
				}

				Button {
					self.exportData()
				} label: {
					if self.isExporting {
						ProgressView()
							.tint(DTColor.textPrimary)
					} else {
						Text(String(localized: "export-account-data"))
					}
				}
				.disabled(self.isExporting || NetworkMonitor.shared.isOffline)
			}
			footer: {
				Text(String(localized: "export-account-data-footer"))
			}
		}
		.task {
			guard !self.isLoaded, let server else { return }
			self.isLoaded = true
			self.sessions = (try? await server.send(User.sessions)) ?? []
			self.recommendations = try? await server.send(Recommendations.settings)
		}
		.toast(self.toast)
	}

	private func setRecommendations(_ enabled: Bool) {
		guard let server else { return }
		self.savingRecommendations = true
		Task {
			defer { self.savingRecommendations = false }
			do {
				self.recommendations = try await server.send(Recommendations.updateSettings(enabled: enabled))
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func revoke(_ session: SessionSummary) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.sendRaw(User.deleteSession(id: session.id))
				self.sessions.removeAll(where: { $0.id == session.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func exportData() {
		guard let server else { return }
		Task {
			self.isExporting = true
			defer { self.isExporting = false }

			do {
				let data = try await server.sendRaw(User.exportAccountData)
				let url = FileManager.default.temporaryDirectory.appendingPathComponent("nafyn-account-export-\(UUID().uuidString).json")
				try data.write(to: url, options: .atomic)
				self.exportedFileURL = url
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
