// Made by Lumaa

import SwiftUI
import Charts
import Safyn

struct StorageSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var info: StorageInfo? = nil
	@State private var selectedAngle: Double?

	private var selectedUsage: StorageInfo.UserUsage? {
		guard let selectedAngle, let info else { return nil }
		var cumulative: Double = 0
		return info.perUser.first { usage in
			cumulative += usage.bytes
			return selectedAngle <= cumulative
		}
	}

	var body: some View {
		Group {
			Section(String(localized: "storage")) {
				if let info {
					VStack(alignment: .leading, spacing: 12) {
						ProgressView(value: info.usedByNafynBytes, total: max(info.totalBytes, 1))
							.tint(DTColor.textPrimary)

						Text("\(self.formatted(info.usedByNafynBytes)) / \(self.formatted(info.totalBytes))")
							.font(.footnote)
							.foregroundStyle(.secondary)

						if !info.perUser.isEmpty {
							Chart(info.perUser, id: \.userId) { usage in
								SectorMark(
									angle: .value("bytes", usage.bytes),
									innerRadius: .ratio(0.55),
									angularInset: 1.5
								)
								.foregroundStyle(by: .value("user", usage.displayName ?? usage.username))
								.cornerRadius(8)
								.opacity(selectedUsage == nil || selectedUsage?.userId == usage.userId ? 1 : 0.4)
							}
							.chartAngleSelection(value: $selectedAngle)
							.chartBackground { proxy in
								GeometryReader { geometry in
									if let plotFrame = proxy.plotFrame, let selectedUsage {
										let frame = geometry[plotFrame]
										VStack(spacing: 2) {
											Text(selectedUsage.displayName ?? selectedUsage.username)
												.font(.footnote.bold())
											Text(self.formatted(selectedUsage.bytes))
												.font(.caption)
												.foregroundStyle(.secondary)
										}
										.position(x: frame.midX, y: frame.midY)
									}
								}
							}
							.frame(height: 200)
							.padding(.vertical, 4)
						}

						ForEach(info.perUser, id: \.userId) { usage in
							HStack {
								Text(usage.displayName ?? usage.username)
								Spacer()
								Text(self.formatted(usage.bytes))
									.foregroundStyle(.secondary)
							}
							.font(.footnote)
							.opacity(selectedUsage == nil || selectedUsage?.userId == usage.userId ? 1 : 0.4)
						}
					}
					.listRowBackground(Color.clear)
				} else {
					VStack(alignment: .leading, spacing: 12) {
						SkeletonBar(height: 8, cornerRadius: 4)
						SkeletonBar(width: 140, height: 12)
						SkeletonBar(height: 200, cornerRadius: 100)
					}
					.listRowBackground(Color.clear)
				}
			}

			Section {
				NavigationLink(value: Navigator.Paths.everyoneLibrary) {
					Text("everyone-library")
				}
			}
		}
		.task {
			guard self.info == nil, let server else { return }
			self.info = try? await server.send(Settings.storage)
		}
	}

	private func formatted(_ bytes: Double) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
	}
}

extension StorageInfo.UserUsage: @retroactive Plottable {
	public var primitivePlottable: Double {
		return self.bytes
	}

	public init?(primitivePlottable: Double) {
		self.init(userId: "unknown", username: "unknown", displayName: nil, bytes: primitivePlottable)
	}
}
