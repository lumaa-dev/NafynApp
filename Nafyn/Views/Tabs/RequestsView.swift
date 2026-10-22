// Made by Lumaa

import SwiftUI
import Safyn

struct RequestsView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var paginator: Paginator<NafynRequest>? = nil
	@State private var toast = ToastState()
	@State private var me: NafynUser? = nil
	@State private var pendingDelete: NafynRequest? = nil

	/// `manageRequests` lets the user accept/deny waiting requests and delete anyone's request.
	private var canManage: Bool {
		self.me?.permissions.has(.manageRequests) ?? false
	}

	/// Anyone can delete their own request; `manageRequests` extends that to everyone's.
	private func canDelete(_ request: NafynRequest) -> Bool {
		if self.canManage { return true }
		guard let me else { return false }

		return switch request.requestedBy {
			case .user(let user): user.id == me.id
			case .id(let id): id == me.id
		}
	}

	var body: some View {
		NavigationStack(path: Binding(get: { Navigator.shared.currentPath[Navigator.Tabs.requests] ?? [] }, set: { Navigator.shared.currentPath[Navigator.Tabs.requests] = $0 })) {
			Group {
				if let paginator {
					PaginatedList(paginator: paginator) { request in
						RequestRow(request: request, canManage: self.canManage) { status in
							self.setStatus(of: request, to: status)
						}
						.swipeActions(edge: .trailing, allowsFullSwipe: false) {
							if self.canDelete(request) {
								Button(role: .destructive) {
									self.pendingDelete = request
								} label: {
									Label(String(localized: "delete"), systemImage: "trash")
								}
								.tint(DTColor.buttonDanger)
								.disabled(NetworkMonitor.shared.isOffline)
							}
						}
					}
				}
			}
			.navigationDestination(for: Navigator.Paths.self) { $0.view }
			.navigationTitle(String(localized: "requests"))
			.toolbarTitleDisplayMode(.inlineLarge)
			.toast(self.toast)
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
					self.paginator = Paginator<NafynRequest> { page, limit in
						try await server.fetchRequests(page: page, limit: limit)
					}
				}
				self.me = try? await server.send(User.me) as NafynUser
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
