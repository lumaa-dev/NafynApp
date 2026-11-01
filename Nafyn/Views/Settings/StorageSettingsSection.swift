// Made by Lumaa

import SwiftUI
import Charts
import Safyn

struct StorageSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
	@State private var info: StorageInfo? = nil

	/// Each user's number of tracks (their public profile's `trackCount`), by user ID. `nil` while loading; a
	/// user whose profile couldn't be read is missing.
	@State private var trackCounts: [String: Int]? = nil

	var body: some View {
		Group {
			Section(String(localized: "storage")) {
				if let info {
					VStack(alignment: .leading, spacing: 12) {
						ProgressView(value: info.usedByNafynBytes, total: max(info.totalBytes, 1))
							.tint(DTColor.textPrimary)

						Text("\(self.formatted(info.usedByNafynBytes)) / \(self.formatted(info.totalBytes))")
							.font(DTFont.text(.footnote))
							.foregroundStyle(.secondary)

						if !info.perUser.isEmpty {
							UserShareChart(
								shares: info.perUser.map { UserShareChart.Share(id: $0.userId, name: Self.name(of: $0), value: $0.bytes) },
								colorNames: Self.names(of: info),
								format: { self.formatted($0) }
							)
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

			if let info, !info.perUser.isEmpty {
				Section(String(localized: "tracks-per-user")) {
					if let trackCounts {
						let shares = info.perUser.compactMap { usage in
							trackCounts[usage.userId].map { UserShareChart.Share(id: usage.userId, name: Self.name(of: usage), value: Double($0)) }
						}

						if shares.contains(where: { $0.value > 0 }) {
							UserShareChart(
								shares: shares,
								colorNames: Self.names(of: info),
								format: { String(localized: "\(Int($0))-tracks") }
							)
							.listRowBackground(Color.clear)
						} else {
							Text("tracks-per-user-empty")
								.font(DTFont.text(.footnote))
								.foregroundStyle(.secondary)
								.listRowBackground(Color.clear)
						}
					} else {
						SkeletonBar(height: 200, cornerRadius: 100)
							.listRowBackground(Color.clear)
					}
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

			guard let users = self.info?.perUser else { return }
			self.trackCounts = await Self.trackCounts(of: users, server: server)
		}
	}

	private func formatted(_ bytes: Double) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
	}

	private static func name(of usage: StorageInfo.UserUsage) -> String {
		usage.displayName ?? usage.username
	}

	/// Every user's name, in the storage chart's order. Both charts color from this list, so a user is the same
	/// color in each even when one of them leaves them out.
	private static func names(of info: StorageInfo) -> [String] {
		info.perUser.map { self.name(of: $0) }
	}

	/// The profiles are read concurrently; a failed one just leaves its user out.
	private static func trackCounts(of users: [StorageInfo.UserUsage], server: NafynServer) async -> [String: Int] {
		await withTaskGroup(of: (String, Int)?.self) { group in
			for user in users {
				group.addTask {
					guard let profile = try? await server.send(Users.profile(username: user.username)) as UserProfile else { return nil }
					return (user.userId, profile.trackCount)
				}
			}

			var counts: [String: Int] = [:]
			for await result in group {
				if let (userId, count) = result {
					counts[userId] = count
				}
			}
			return counts
		}
	}
}

/// A donut chart of how something is split between users, with the per-user figures listed under it. Tapping
/// the chart highlights one user.
///
/// Colors come from a fixed palette indexed by the user's place in `colorNames`, not from the data shown, so two
/// charts given the same `colorNames` paint every user the same.
private struct UserShareChart: View {
	struct Share: Identifiable {
		let id: String
		let name: String
		let value: Double
	}

	let shares: [Share]
	let colorNames: [String]
	let format: (Double) -> String

	@State private var selectedAngle: Double?

	private static let palette: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .yellow, .pink, .mint, .indigo, .teal, .brown]

	private var selected: Share? {
		guard let selectedAngle else { return nil }
		var cumulative: Double = 0
		return self.shares.first { share in
			cumulative += share.value
			return selectedAngle <= cumulative
		}
	}

	private var colors: [Color] {
		self.colorNames.indices.map { Self.palette[$0 % Self.palette.count] }
	}

	var body: some View {
		let selected = self.selected

		VStack(alignment: .leading, spacing: 12) {
			Chart(self.shares) { share in
				SectorMark(
					angle: .value("value", share.value),
					innerRadius: .ratio(0.55),
					angularInset: 1.5
				)
				.foregroundStyle(by: .value("user", share.name))
				.cornerRadius(8)
				.opacity(selected == nil || selected?.id == share.id ? 1 : 0.4)
			}
			.chartForegroundStyleScale(domain: self.colorNames, range: self.colors)
			.chartAngleSelection(value: self.$selectedAngle)
			.chartBackground { proxy in
				GeometryReader { geometry in
					if let plotFrame = proxy.plotFrame, let selected {
						let frame = geometry[plotFrame]
						VStack(spacing: 2) {
							Text(selected.name)
								.font(DTFont.text(.footnote, weight: .bold))
							Text(self.format(selected.value))
								.font(DTFont.text(.caption))
								.foregroundStyle(.secondary)
						}
						.position(x: frame.midX, y: frame.midY)
					}
				}
			}
			.frame(height: 200)
			.padding(.vertical, 4)

			ForEach(self.shares) { share in
				HStack {
					Text(share.name)
					Spacer()
					Text(self.format(share.value))
						.foregroundStyle(.secondary)
				}
				.font(DTFont.text(.footnote))
				.opacity(selected == nil || selected?.id == share.id ? 1 : 0.4)
			}
		}
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
