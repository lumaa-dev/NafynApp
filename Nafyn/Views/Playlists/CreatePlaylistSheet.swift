// Made by Lumaa

import SwiftUI
import Safyn

struct CreatePlaylistSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var onCreated: (PlaylistRow) -> Void

	@State private var title: String = ""
	@State private var description: String = ""
	@State private var privacy: PlaylistPrivacy = .private
	@State private var toast = ToastState()
	@State private var isCreating = false

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(String(localized: "title"), text: self.$title)
					TextField(String(localized: "description"), text: self.$description)
				}

				Section {
					Picker(String(localized: "privacy"), selection: self.$privacy) {
						Text("private").tag(PlaylistPrivacy.private)
						Text("public").tag(PlaylistPrivacy.public)
					}
				}
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.navigationTitle(String(localized: "new-playlist"))
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
						self.create()
					} label: {
						Label(String(localized: "create"), systemImage: "checkmark")
							.labelStyle(.iconOnly)
					}
					.disabled(self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.isCreating || NetworkMonitor.shared.isOffline)
					.tint(Color.accentColor)
				}
			}
			.toast(self.toast)
		}
	}

	private func create() {
		guard let server, !self.isCreating else { return }
		self.isCreating = true

		Task {
			defer { self.isCreating = false }
			do {
				let playlist = try await server.send(Playlist.create(
					title: self.title,
					description: self.description.isEmpty ? nil : self.description,
					privacy: self.privacy
				)) as PlaylistRow
				self.onCreated(playlist)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
