// Made by Lumaa

import SwiftUI
import Charts
import Safyn

struct StorageSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var info: StorageInfo? = nil

	var body: some View {
		Group {
			Section(String(localized: "storage")) {
				if let info {
					VStack(alignment: .leading, spacing: 12) {
						ProgressView(value: info.usedByNafynBytes, total: max(info.totalBytes, 1))

						Text("\(Self.formatted(info.usedByNafynBytes)) / \(Self.formatted(info.totalBytes))")
							.font(.footnote)
							.foregroundStyle(.secondary)

						if !info.perUser.isEmpty {
							Chart(info.perUser, id: \.userId) { usage in
								SectorMark(angle: .value("bytes", usage.bytes), innerRadius: .ratio(0.55), angularInset: 1.5)
									.foregroundStyle(by: .value("user", usage.displayName ?? usage.username))
									.cornerRadius(4)
							}
							.frame(height: 200)
							.padding(.vertical, 4)
						}

						ForEach(info.perUser, id: \.userId) { usage in
							HStack {
								Text(usage.displayName ?? usage.username)
								Spacer()
								Text(Self.formatted(usage.bytes))
									.foregroundStyle(.secondary)
							}
							.font(.footnote)
						}
					}
					.listRowBackground(Color.clear)
				} else {
					ProgressView()
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

	private static func formatted(_ bytes: Double) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
	}
}
