// Made by Lumaa

import SwiftUI
import PhotosUI
import Safyn

/// The "profile" section (avatar) plus an unheaded section for the editable profile fields, matching
/// the web app's settings layout — avatar upload is visually separate from the text fields below it.
struct ProfileSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	var user: NafynUser
	var onUpdated: (NafynUser) -> Void

	@State private var displayName: String
	@State private var lastFm: String
	@State private var discogs: String
	@State private var toast = ToastState()
	@State private var isSaving = false
	@State private var isUploadingAvatar = false
	@State private var avatarPickerItem: PhotosPickerItem? = nil

	/// `NafynUser.avatar` is NOT a URL — confirmed against `user/avatar.post.ts`, it's just a
	/// cache-busting timestamp string (`Date.now().toString()`) the server bumps on every upload. The
	/// actual image lives behind the authenticated `User.avatar(id:token:)` endpoint (same pattern as a
	/// playlist's `image` field). Folding that timestamp into the URL as a query item both builds the
	/// right URL and — as a free side effect — busts `AsyncImage`'s cache on every new upload.
	private var avatarURL: URL? {
		guard let avatarVersion = self.user.avatar, let server else { return nil }
		let endpoint = User.avatar(id: self.user.id, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		components.queryItems = endpoint.queries + [URLQueryItem(name: "v", value: avatarVersion)]
		return components.url
	}

	init(user: NafynUser, onUpdated: @escaping (NafynUser) -> Void) {
		self.user = user
		self.onUpdated = onUpdated
		self._displayName = State(initialValue: user.displayName ?? "")
		self._lastFm = State(initialValue: user.lastFm ?? "")
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
					.disabled(self.isUploadingAvatar)

					Spacer()
				}
				.listRowBackground(Color.clear)
			}

			Section {
				TextField(String(localized: "display-name"), text: self.$displayName)
				TextField(String(localized: "lastfm-username"), text: self.$lastFm)
					.autocorrectionDisabled()
				TextField(String(localized: "discogs-username"), text: self.$discogs)
					.autocorrectionDisabled()

				Button(String(localized: "save")) {
					self.saveProfile()
				}
				.disabled(self.isSaving)
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
					lastFm: self.lastFm.isEmpty ? .clear : .value(self.lastFm),
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
