// Made by Lumaa

import SwiftUI
import Safyn

struct RequestsView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var paginator: Paginator<NafynRequest>? = nil
	@State private var toast = ToastState()
	@State private var me: NafynUser? = nil
	@State private var pendingDelete: NafynRequest? = nil

	/// Statuses to show; empty means "All". Several can be active at once.
	@State private var filters: Set<RequestFilter> = []

	/// Bumped whenever `filters` changes, so `PaginatedList` (which only reads its paginator once) starts over.
	@State private var listGeneration = 0

	/// `manageRequests` lets the user accept/deny waiting requests and delete anyone's request.
	private var canManage: Bool {
		self.me?.permissions.has(.manageRequests) ?? false
	}

	private var isFiltering: Bool {
		!self.filters.isEmpty
	}

	private func makePaginator(server: NafynServer) -> Paginator<NafynRequest> {
		let filters = self.filters
		return Paginator<NafynRequest> { page, limit in
			try await server.fetchRequests(page: page, limit: limit, filters: filters)
		}
	}

	var body: some View {
		NavigationStack(path: Binding(get: { Navigator.shared.currentPath[Navigator.Tabs.requests] ?? [] }, set: { Navigator.shared.currentPath[Navigator.Tabs.requests] = $0 })) {
			Group {
				if let paginator {
					PaginatedList(paginator: paginator) { request in
						RequestRow(request: request, canManage: self.canManage, onDecision: { status in
							self.setStatus(of: request, to: status)
						}, onDelete: {
							self.pendingDelete = request
						})
					}
					// `PaginatedList` reads its paginator once: a new filter needs a new list
					.id(self.listGeneration)
				}
			}
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "requests"))
			.toolbarTitleDisplayMode(.inlineLarge)
			.toast(self.toast)
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					self.filterMenu
				}
			}
			.alert(
				String(localized: "delete-request-confirm"),
				isPresented: Binding(get: { self.pendingDelete != nil }, set: { if !$0 { self.pendingDelete = nil } }),
				presenting: self.pendingDelete
			) { request in
				Button(String(localized: "cancel"), role: .cancel) {}
				Button(String(localized: "delete"), role: .destructive) {
					self.delete(request)
				}
			}
			.task {
				guard let server else { return }
				if self.paginator == nil {
					self.paginator = self.makePaginator(server: server)
				}
				self.me = try? await server.send(User.me) as NafynUser
			}
		}
	}

	/// "All" plus one toggle per status. "All" is on only while no status is picked; picking a status turns it
	/// off, and clearing the last one turns it back on. The icon fills while a filter is active.
	private var filterMenu: some View {
		Menu {
			Toggle(isOn: Binding(get: { !self.isFiltering }, set: { _ in self.setFilters([]) })) {
				Label(String(localized: "all"), systemImage: "tray.full")
			}
			.tint(Color.primary)

			Divider()

			ForEach(RequestFilter.allCases) { filter in
				Toggle(isOn: Binding(
					get: { self.filters.contains(filter) },
					set: { isOn in
						var updated = self.filters
						if isOn { updated.insert(filter) } else { updated.remove(filter) }
						self.setFilters(updated)
					}
				)) {
					Label(filter.title, systemImage: filter.symbol)
				}
				.tint(Color.primary)
			}
		} label: {
			Label(String(localized: "filter"), systemImage: self.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
				.labelStyle(.iconOnly)
		}
		.menuActionDismissBehavior(.disabled)
		.tint(Color.primary)
	}

	private func setFilters(_ new: Set<RequestFilter>) {
		guard new != self.filters, let server else { return }
		self.filters = new
		self.paginator = self.makePaginator(server: server)
		self.listGeneration += 1
	}

	private func delete(_ request: NafynRequest) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.sendRaw(Request.delete(id: request.id))
				self.paginator?.remove(where: { $0.id == request.id })
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func setStatus(of request: NafynRequest, to status: RequestStatus) {
		guard let server else { return }
		Task {
			do {
				// raw: the response's compact `requestedBy` doesn't decode as a full `NafynRequest`
				_ = try await server.sendRaw(Request.updateStatus(requestId: request.id, status: status))
				self.paginator?.update(id: request.id) { item in
					item = NafynRequest(id: item.id, musicbrainzId: item.musicbrainzId, info: item.info, type: item.type, status: status, requestedBy: item.requestedBy, createdAt: item.createdAt, updatedAt: .now)
				}
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

/// A status group the Requests list can be narrowed to. The server filters the first four itself; `denied`
/// has no server filter (it is always listed), so ``NafynServer/fetchRequests(page:limit:filters:)`` drops
/// those client-side unless picked.
enum RequestFilter: String, CaseIterable, Identifiable, Hashable {
	case waiting
	case inProgress
	case succeeded
	case failed
	case denied

	var id: String { self.rawValue }

	var title: String {
		switch self {
			case .waiting: String(localized: "status-waiting")
			case .inProgress: String(localized: "status-in-progress")
			case .succeeded: String(localized: "status-completed")
			case .failed: String(localized: "status-failed")
			case .denied: String(localized: "status-denied")
		}
	}

	var symbol: String {
		switch self {
			case .waiting: "clock"
			case .inProgress: "arrow.down.circle"
			case .succeeded: "checkmark.circle"
			case .failed: "exclamationmark.triangle"
			case .denied: "xmark.circle"
		}
	}
}
