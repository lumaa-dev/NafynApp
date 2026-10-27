// Made by Lumaa

import SwiftUI
import Safyn

struct PlaylistMembersSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var playlistId: String
	var owner: NafynUser
	var isOwner: Bool
	@State var members: [NafynUser]
	var onMembersChanged: ([NafynUser]) -> Void

	@State private var newUsername: String = ""
	@State private var toast = ToastState()
	@State private var isAdding = false

	var body: some View {
		NavigationStack {
			List {
				Section(String(localized: "owner")) {
					Text(self.owner.displayName ?? self.owner.username)
				}

				Section(String(localized: "members")) {
					ForEach(self.members, id: \.id) { member in
						Text(member.displayName ?? member.username)
							.swipeActions {
								if self.isOwner {
									Button(role: .destructive) {
										self.remove(member)
									} label: {
										Label(String(localized: "remove"), systemImage: "trash")
									}
									.tint(DTColor.buttonDanger)
									.disabled(NetworkMonitor.shared.isOffline)
								}
							}
					}

					if self.isOwner {
						HStack {
							TextField(String(localized: "username"), text: self.$newUsername)
								.textFieldStyle(.pill)
								.autocorrectionDisabled()
								#if !os(macOS)
								.textInputAutocapitalization(.never)
								#endif

							Button {
								self.add()
							} label: {
								Image(systemName: "plus.circle.fill")
							}
							.buttonStyle(.plain)
							.disabled(self.newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.isAdding || NetworkMonitor.shared.isOffline)
						}
					}
				}
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.navigationTitle(String(localized: "members"))
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "done"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
			.toast(self.toast)
		}
	}

	private func add() {
		guard let server, !self.isAdding else { return }
		self.isAdding = true
		let username = self.newUsername

		Task {
			defer { self.isAdding = false }
			do {
				_ = try await server.send(Playlist.addMember(pid: self.playlistId, username: username)) as PlaylistMemberRow
				self.newUsername = ""
				// PlaylistMemberRow only carries the new member's userId, not a resolved NafynUser —
				// refetch the playlist so the member list shows real display names.
				let detail = try await server.fetchPlaylistDetail(pid: self.playlistId)
				self.members = detail.members
				self.onMembersChanged(self.members)
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func remove(_ member: NafynUser) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Playlist.removeMember(pid: self.playlistId, uid: member.id)) as RemovedResponse
				self.members.removeAll(where: { $0.id == member.id })
				self.onMembersChanged(self.members)
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
