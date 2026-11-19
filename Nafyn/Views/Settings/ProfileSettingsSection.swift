// Made by Lumaa

import SwiftUI
import PhotosUI
import Safyn

/// The "profile" section (avatar) plus an unheaded section for the editable profile fields, matching
/// the web app's settings layout — avatar upload is visually separate from the text fields below it. Lives in
/// the profile screen's edit sheet (``ProfileEditSheet``).
struct ProfileSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	var user: NafynUser
	var onUpdated: (NafynUser) -> Void

	@State private var displayName: String
	@State private var listenBrainz: String
	@State private var discogs: String
	@State private var toast = ToastState()
	@State private var isSaving = false
	@State private var isUploadingAvatar = false
	@State private var avatarPickerItem: PhotosPickerItem? = nil

	private var avatarURL: URL? {
		self.server?.avatarURL(userId: self.user.id, version: self.user.avatar)
	}

	/// Called once the profile fields were saved (the avatar uploads on its own).
	var onSaved: (() -> Void)? = nil

	init(user: NafynUser, onSaved: (() -> Void)? = nil, onUpdated: @escaping (NafynUser) -> Void) {
		self.user = user
		self.onSaved = onSaved
		self.onUpdated = onUpdated
		self._displayName = State(initialValue: user.displayName ?? "")
		self._listenBrainz = State(initialValue: user.listenBrainz ?? "")
		self._discogs = State(initialValue: user.discogs ?? "")
	}

	var body: some View {
		Group {
			Section(String(localized: "profile")) {
				HStack {
					Spacer()

					PhotosPicker(selection: self.$avatarPickerItem, matching: .images) {
						ZStack {
							CoverImage(url: self.avatarURL)
								.clipShape(Circle())
								.frame(width: 84, height: 84)

							if self.isUploadingAvatar {
								Circle()
									.fill(.black.opacity(0.4))
									.frame(width: 84, height: 84)
								ProgressView()
									.tint(DTColor.textPrimary)
							}
						}
					}
					.disabled(self.isUploadingAvatar || NetworkMonitor.shared.isOffline)

					Spacer()
				}
				.listRowBackground(Color.clear)
			}

			Section {
				TextField(String(localized: "display-name"), text: self.$displayName)
				TextField(String(localized: "listenbrainz-username"), text: self.$listenBrainz)
					.autocorrectionDisabled()
				TextField(String(localized: "discogs-username"), text: self.$discogs)
					.autocorrectionDisabled()

				Button(String(localized: "save")) {
					self.saveProfile()
				}
				.disabled(self.isSaving || NetworkMonitor.shared.isOffline)
			}
		}
		.toast(self.toast)
		.onChange(of: self.avatarPickerItem) { _, newItem in
			guard let newItem else { return }
			Task { await self.uploadAvatar(newItem) }
		}
	}

	private func saveProfile() {
		guard let server, !self.isSaving else { return }
		self.isSaving = true

		Task {
			defer { self.isSaving = false }
			do {
				let updated = try await server.send(User.updateProfile(
					displayName: self.displayName.isEmpty ? nil : self.displayName,
					listenBrainz: self.listenBrainz.isEmpty ? .clear : .value(self.listenBrainz),
					discogs: self.discogs.isEmpty ? .clear : .value(self.discogs)
				)) as NafynUser
				self.onUpdated(updated)
				self.toast.success(String(localized: "saved"))
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func uploadAvatar(_ item: PhotosPickerItem) async {
		guard let server, !self.isUploadingAvatar else { return }
		self.isUploadingAvatar = true
		defer { self.isUploadingAvatar = false }

		do {
			guard let data = try await item.loadTransferable(type: Data.self) else {
				self.toast.failure(NafynError.decoding("Could not read the selected photo"))
				return
			}
			let updated = try await server.send(User.setAvatar(data: data, filename: "avatar.jpg", mimeType: "image/jpeg")) as NafynUser
			self.onUpdated(updated)
		} catch {
			self.toast.failure(error)
		}
	}
}
