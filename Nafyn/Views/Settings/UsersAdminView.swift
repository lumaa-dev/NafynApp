// Made by Lumaa

import SwiftUI
import Safyn

struct UsersAdminView: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var paginator: Paginator<NafynUser>? = nil
	@State private var editingUser: NafynUser? = nil
	@State private var currentUserId: String? = nil
	@State private var currentPermissions: Permissions = []

	var body: some View {
		Group {
			if let paginator {
				PaginatedList(paginator: paginator) { user in
					self.row(user)
				}
			} else {
				List {
					SkeletonTrackRows()
						.listRowBackground(Color.clear)
				}
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
			}
		}
		.task {
			guard self.paginator == nil, let server else { return }
			self.paginator = Paginator<NafynUser> { page, limit in
				try await server.fetchPaginated(path: "/api/v1/users", page: page, limit: limit)
			}
			if let me = try? await server.send(User.me) as NafynUser {
				self.currentUserId = me.id
				self.currentPermissions = me.permissions
			}
		}
		.navigationTitle(String(localized: "users"))
		.sheet(item: self.$editingUser) { user in
			EditUserSheet(user: user) { updated in
				self.paginator?.update(id: updated.id) { $0 = updated }
			} onDeleted: {
				self.paginator?.remove(where: { $0.id == user.id })
			}
		}
	}

	@ViewBuilder
	private func row(_ user: NafynUser) -> some View {
		let canManage = self.currentUserId.map { Permissions.canManageAccount(actorId: $0, actorPermissions: self.currentPermissions, targetId: user.id, targetPermissions: user.permissions) } ?? false

		Button {
			guard canManage else { return }
			self.editingUser = user
		} label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(user.displayName ?? user.username)
						.foregroundStyle(DTColor.textPrimary)
					Text("@\(user.username)")
						.font(DTFont.system(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				}

				Spacer()

				if !canManage {
					Image(systemName: "lock")
						.foregroundStyle(DTColor.textPrimary.opacity(0.3))
				}
			}
		}
		.buttonStyle(.plain)
		.disabled(!canManage)
	}
}

extension Permissions {
	/// Whether the server lets this actor edit or delete that account (`canManageUser` in the server's
	/// `entity/Permission.ts`). Safyn's `Permissions.canManage(...)` still follows the older rule, where an
	/// `admin` could edit anyone and a `manageAccounts` holder themselves; the server now answers 401 to both.
	///
	/// - Nobody edits themselves through the accounts routes (their own profile lives in Settings > Profile).
	/// - `admin` edits anyone except another `admin`.
	/// - `manageAccounts` edits only accounts that hold neither `manageAccounts` nor `admin`.
	static func canManageAccount(actorId: String, actorPermissions: Permissions, targetId: String, targetPermissions: Permissions) -> Bool {
		if actorId == targetId { return false }
		if actorPermissions.contains(.admin) { return !targetPermissions.contains(.admin) }
		if actorPermissions.contains(.manageAccounts) { return targetPermissions.isDisjoint(with: [.manageAccounts, .admin]) }
		return false
	}
}

private struct EditUserSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var user: NafynUser
	var onUpdated: (NafynUser) -> Void
	var onDeleted: () -> Void

	@State private var displayName: String
	@State private var username: String
	@State private var lastFm: String
	@State private var discogs: String
	@State private var permissions: Permissions
	@State private var toast = ToastState()
	@State private var isSaving = false
	@State private var showDeleteConfirm = false

	init(user: NafynUser, onUpdated: @escaping (NafynUser) -> Void, onDeleted: @escaping () -> Void) {
		self.user = user
		self.onUpdated = onUpdated
		self.onDeleted = onDeleted
		self._displayName = State(initialValue: user.displayName ?? "")
		self._username = State(initialValue: user.username)
		self._lastFm = State(initialValue: user.lastFm ?? "")
		self._discogs = State(initialValue: user.discogs ?? "")
		self._permissions = State(initialValue: user.permissions)
	}

	private static let allPermissions: [(Permissions, String)] = [
		(.requestAlbums, "request-albums"),
		(.requestTracks, "request-tracks"),
		(.manageRequests, "manage-requests"),
		(.autoacceptAlbums, "autoaccept-albums"),
		(.autoacceptTracks, "autoaccept-tracks"),
		(.manageAccounts, "manage-accounts"),
		(.manageMusic, "manage-music"),
		(.manageNotifications, "manage-notifications"),
		(.manageWebhooks, "manage-webhooks"),
		(.admin, "admin"),
	]

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(String(localized: "display-name"), text: self.$displayName)
					TextField(String(localized: "username"), text: self.$username)
						.autocorrectionDisabled()
					TextField(String(localized: "lastfm-username"), text: self.$lastFm)
						.autocorrectionDisabled()
					TextField(String(localized: "discogs-username"), text: self.$discogs)
						.autocorrectionDisabled()
				}
				.sheetRows()

				Section(String(localized: "permissions")) {
					ForEach(Self.allPermissions, id: \.1) { permission, key in
						Toggle(String(localized: String.LocalizationValue(key)), isOn: Binding(
							get: { self.permissions.contains(permission) },
							set: { isOn in
								if isOn {
									self.permissions.insert(permission)
								} else {
									self.permissions.remove(permission)
								}
							}
						))
					}
				}
				.sheetRows()

				Section {
					Button(String(localized: "delete-account"), role: .destructive) {
						self.showDeleteConfirm = true
					}
					.disabled(NetworkMonitor.shared.isOffline)
				}
				.sheetRows()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.navigationTitle(self.user.username)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "cancel"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button {
						self.save()
					} label: {
						Label(String(localized: "save"), systemImage: "checkmark")
							.labelStyle(.iconOnly)
					}
					.disabled(self.isSaving || NetworkMonitor.shared.isOffline)
					.tint(Color.accentColor)
				}
			}
			.toast(self.toast)
			.alert(String(localized: "delete-account-confirm"), isPresented: self.$showDeleteConfirm) {
				Button(String(localized: "cancel"), role: .cancel) {}
				Button(String(localized: "delete"), role: .destructive) {
					self.delete()
				}
			}
		}
		.sheetBackground()
	}

	private func save() {
		guard let server, !self.isSaving else { return }
		self.isSaving = true

		Task {
			defer { self.isSaving = false }
			do {
				let updated = try await server.send(Users.update(
					id: self.user.id,
					displayName: self.displayName.isEmpty ? nil : self.displayName,
					username: self.username == self.user.username ? nil : self.username,
					lastFm: self.lastFm.isEmpty ? .clear : .value(self.lastFm),
					discogs: self.discogs.isEmpty ? .clear : .value(self.discogs),
					permissions: self.permissions
				)) as NafynUser
				self.onUpdated(updated)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func delete() {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Users.delete(id: self.user.id)) as RemovedResponse
				self.onDeleted()
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
