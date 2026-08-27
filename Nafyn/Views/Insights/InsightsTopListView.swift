// Made by Lumaa

import SwiftUI
import Safyn

/// The full ranked list behind a "see all" on any Insights screen, from `Insights.top(...)`.
struct InsightsTopListView: View {
	@Environment(\.server) private var server: NafynServer?

	let type: RankedEntityKind
	let period: String
	var year: Int? = nil
	var month: String? = nil

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.insightsTop(type: self.type, period: self.period, month: self.month, year: self.year)
		} skeleton: {
			AnyView(SkeletonTrackRows())
		} content: { entities, _ in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					if entities.isEmpty {
						Text(String(localized: "insights-no-data"))
							.font(DTFont.system(15))
							.foregroundStyle(DTColor.textPrimary.opacity(0.6))
							.frame(maxWidth: .infinity)
							.padding(.vertical, 40)
					} else {
						ForEach(entities) { entity in
							RankedEntityRow(entity: entity) {
								entity.navigate()
							}
						}
					}
				}
				.padding(.horizontal)
				.padding(.vertical)
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.background(DTColor.background.ignoresSafeArea())
		}
		.navigationTitle(self.title)
		.navigationBarTitleDisplayMode(.inline)
	}

	private var title: String {
		switch self.type {
			case .track:
				return String(localized: "top-tracks")
			case .album:
				return String(localized: "top-albums")
			case .artist:
				return String(localized: "top-artists")
			case .playlist:
				return String(localized: "top-playlists")
		}
	}
}
