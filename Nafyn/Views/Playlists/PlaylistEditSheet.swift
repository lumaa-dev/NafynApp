// Made by Lumaa

import SwiftUI
import Safyn

struct PlaylistEditSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	var playlist: PlaylistRow
	var onUpdated: (PlaylistRow) -> Void

	@State private var title: String
	@State private var description: String
	@State private var privacy: PlaylistPrivacy
	@State private var sortMode: PlaylistSortMode
	@State private var toast = ToastState()
	@State private var isSaving = false

	init(playlist: PlaylistRow, onUpdated: @escaping (PlaylistRow) -> Void) {
		self.playlist = playlist
		self.onUpdated = onUpdated
		self._title = State(initialValue: playlist.title)
		self._description = State(initialValue: playlist.description ?? "")
		self._privacy = State(initialValue: playlist.privacy)
		self._sortMode = State(initialValue: playlist.sortMode)
	}

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

					Picker(String(localized: "sort"), selection: self.$sortMode) {
						Text("manual").tag(PlaylistSortMode.manual)
						Text("title").tag(PlaylistSortMode.title)
						Text("artist").tag(PlaylistSortMode.artist)
						Text("added-by").tag(PlaylistSortMode.addedBy)
						Text("duration").tag(PlaylistSortMode.duration)
					}
				}
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
			.navigationTitle(String(localized: "edit-playlist"))
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "cancel")) { self.dismiss() }
						.tint(Color.primary)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(String(localized: "save")) {
						self.save()
					}
					.disabled(self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.isSaving || NetworkMonitor.shared.isOffline)
					.tint(Color.primary)
				}
			}
			.toast(self.toast)
		}
	}

	private func save() {
		guard let server, !self.isSaving else { return }
		self.isSaving = true

		let descriptionPatch: Patchable<String> = self.description.isEmpty ? .clear : .value(self.description)

		Task {
			defer { self.isSaving = false }
			do {
				let updated = try await server.send(Playlist.update(
					pid: self.playlist.id,
					title: self.title,
					description: descriptionPatch,
					privacy: self.privacy,
					sortMode: self.sortMode
				)) as PlaylistRow
				self.onUpdated(updated)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
