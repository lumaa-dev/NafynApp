// Made by Lumaa

import SwiftUI
import Safyn

struct RequestsView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var paginator: Paginator<NafynRequest>? = nil
	@State private var toast = ToastState()
	@State private var me: NafynUser? = nil
	@State private var pendingDelete: NafynRequest? = nil
	@State private var pendingCancel: NafynRequest? = nil

	/// Statuses to show; empty means "All". Several can be active at once.
	@State private var filters: Set<RequestFilter> = []

	/// Only album or only track requests; `nil` shows both.
	@State private var typeFilter: RequestKind? = nil
	/// Only this account's requests (managers only, who see everyone's); `nil` shows everyone's.
	@State private var userFilter: String? = nil
	/// Who made a request, for the "Requested by" filter (loaded for managers only).
	@State private var requesters: [RequestRequester] = []

	/// Bumped whenever `filters` changes, so `PaginatedList` (which only reads its paginator once) starts over.
	@State private var listGeneration = 0

	/// `manageRequests` lets the user accept/deny waiting requests and delete anyone's request.
	private var canManage: Bool {
		self.me?.permissions.has(.manageRequests) ?? false
	}

	private var isFiltering: Bool {
		!self.filters.isEmpty || self.typeFilter != nil || self.userFilter != nil
	}

	private func makePaginator(server: NafynServer) -> Paginator<NafynRequest> {
		let filters = self.filters
		let type = self.typeFilter
		let user = self.userFilter
		return Paginator<NafynRequest> { page, limit in
			try await server.fetchRequests(page: page, limit: limit, filters: filters, type: type, user: user)
		}
	}

	var body: some View {
		NavigationStack(path: Navigator.shared.path(for: .requests)) {
			Group {
				if let paginator {
					PaginatedList(paginator: paginator) { request in
						RequestRow(request: request, canManage: self.canManage, onDecision: { status in
							self.setStatus(of: request, to: status)
						}, onDelete: {
							self.pendingDelete = request
						}, canCancel: self.canManage || self.isMine(request), onCancel: {
							self.pendingCancel = request
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
			.alert(
				String(localized: "cancel-request-confirm"),
				isPresented: Binding(get: { self.pendingCancel != nil }, set: { if !$0 { self.pendingCancel = nil } }),
				presenting: self.pendingCancel
			) { request in
				Button(String(localized: "keep-request"), role: .cancel) {}
				Button(String(localized: "cancel-request"), role: .destructive) {
					self.cancel(request)
				}
			} message: { _ in
				Text("cancel-request-message")
			}
			.task {
				guard let server else { return }
				if self.paginator == nil {
					self.paginator = self.makePaginator(server: server)
				}
				// once: the task runs again every time the screen re-appears
				guard self.me == nil else { return }
				self.me = try? await server.send(User.me) as NafynUser
				// only managers see other people's requests, so only they get "Requested by" (silent on failure:
				// the menu then simply has no such filter)
				if self.canManage {
					self.requesters = (try? await server.send(Request.requesters) as [RequestRequester]) ?? []
				}
			}
		}
	}

	/// "All" plus one toggle per status. "All" is on only while no status is picked; picking a status turns it
	/// off, and clearing the last one turns it back on. The icon fills while a filter is active.
	private var filterMenu: some View {
		Menu {
			Toggle(isOn: Binding(get: { !self.isFiltering }, set: { _ in self.clearFilters() })) {
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

			Divider()

			Picker(selection: Binding(get: { self.typeFilter }, set: { self.setType($0) })) {
				Label(String(localized: "all-types"), systemImage: "square.stack")
					.tag(RequestKind?.none)
				Label(String(localized: "albums"), systemImage: "square.stack.fill")
					.tag(RequestKind?.some(.album))
				Label(String(localized: "tracks"), systemImage: "music.note")
					.tag(RequestKind?.some(.track))
			} label: {
				Label(String(localized: "request-type"), systemImage: "square.stack")
			}
			.pickerStyle(.menu)
			.tint(Color.primary)

			if self.canManage, !self.requesters.isEmpty {
				Picker(selection: Binding(get: { self.userFilter }, set: { self.setUser($0) })) {
					Label(String(localized: "everyone"), systemImage: "person.2")
						.tag(String?.none)
					ForEach(self.requesters) { requester in
						Label(requester.id == self.me?.id ? String(localized: "you-name-\(requester.name)") : requester.name, systemImage: "person")
							.tag(String?.some(requester.id))
					}
				} label: {
					Label(String(localized: "requested-by"), systemImage: "person.2")
				}
				.pickerStyle(.menu)
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
		guard new != self.filters else { return }
		self.filters = new
		self.reload()
	}

	private func setType(_ new: RequestKind?) {
		guard new != self.typeFilter else { return }
		self.typeFilter = new
		self.reload()
	}

	private func setUser(_ new: String?) {
		guard new != self.userFilter else { return }
		self.userFilter = new
		self.reload()
	}

	/// "All": every status, both types, everyone.
	private func clearFilters() {
		guard self.isFiltering else { return }
		self.filters = []
		self.typeFilter = nil
		self.userFilter = nil
		self.reload()
	}

	/// `PaginatedList` reads its paginator once: a new filter needs a new list.
	private func reload() {
		guard let server else { return }
		self.paginator = self.makePaginator(server: server)
		self.listGeneration += 1
	}

	private func isMine(_ request: NafynRequest) -> Bool {
		guard let me else { return false }
		switch request.requestedBy {
			case .user(let user): return user.id == me.id
			case .id(let id): return id == me.id
		}
	}

	/// The server stops a waiting request at once and one in the pipeline at its next step; the row's live socket
	/// then reports `cancelled`, so the list row is only patched for the immediate case.
	private func cancel(_ request: NafynRequest) {
		guard let server else { return }
		Task {
			do {
				let response: CancelRequestResponse = try await server.send(Request.cancel(id: request.id))
				if response.status == .cancelled {
					self.paginator?.update(id: request.id) { item in
						item = NafynRequest(id: item.id, musicbrainzId: item.musicbrainzId, info: item.info, type: item.type, status: .cancelled, requestedBy: item.requestedBy, createdAt: item.createdAt, updatedAt: .now)
					}
				}
				self.toast.success(String(localized: "request-cancelled"))
			} catch {
				self.toast.failure(error)
			}
		}
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
	case cancelled

	var id: String { self.rawValue }

	var title: String {
		switch self {
			case .waiting: String(localized: "status-waiting")
			case .inProgress: String(localized: "status-in-progress")
			case .succeeded: String(localized: "status-completed")
			case .failed: String(localized: "status-failed")
			case .denied: String(localized: "status-denied")
			case .cancelled: String(localized: "status-cancelled")
		}
	}

	var symbol: String {
		switch self {
			case .waiting: "clock"
			case .inProgress: "arrow.down.circle"
			case .succeeded: "checkmark.circle"
			case .failed: "exclamationmark.triangle"
			case .denied: "xmark.circle"
			case .cancelled: "stop.circle"
		}
	}
}
