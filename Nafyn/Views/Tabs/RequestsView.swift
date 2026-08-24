// Made by Lumaa

import SwiftUI
import Safyn

struct RequestsView: View {
	@Environment(\.server) private var server: NafynServer?

	var body: some View {
		NavigationStack(path: Binding(get: { Navigator.shared.currentPath[Navigator.Tabs.requests] ?? [] }, set: { Navigator.shared.currentPath[Navigator.Tabs.requests] = $0 })) {
			Group {
				if let server {
					PaginatedList(paginator: Paginator<NafynRequest> { page, limit in
						try await server.fetchRequests(page: page, limit: limit)
					}) { request in
						RequestRow(request: request)
					}
				}
			}
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "requests"))
		}
	}
}
