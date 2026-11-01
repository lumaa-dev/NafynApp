// Made by Lumaa

import SwiftUI
import Safyn

/// Puts an owned track on another album: "Bad Decisions" came out as a single and belongs on "The New
/// Abnormal". Searches MusicBrainz (starting from the track's artist), then `Library.changeAlbum` moves the track:
/// the server takes the album's title, cover, date and the track's place on it, and moves the file. Mirrors the
/// web app's `ChangeAlbumModal.vue`.
struct ChangeAlbumSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	let trackId: String

	@State private var track: MediaRow? = nil
	@State private var query = ""
	@State private var albums: [MediaInfo] = []
	@State private var isSearching = false
	@State private var hasSearched = false
	@State private var pending: MediaInfo? = nil
	@State private var movingTo: String? = nil
	@State private var toast = ToastState()

	var body: some View {
		NavigationStack {
			List {
				if let track {
					Text("change-album-intro \(track.title) \(track.artistName)")
						.font(DTFont.system(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.7))
						.listRowBackground(Color.clear)
				}

				if self.isSearching && self.albums.isEmpty {
					SkeletonTrackRows(count: 5)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				} else if self.hasSearched && self.albums.isEmpty {
					Text("no-results")
						.font(DTFont.system(18))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
						.frame(maxWidth: .infinity)
						.padding(.top, 30)
						.listRowSeparator(.hidden)
						.listRowBackground(Color.clear)
				}

				ForEach(self.albums, id: \.id) { album in
					Button {
						self.pending = album
					} label: {
						self.row(album)
					}
					.disabled(self.movingTo != nil || NetworkMonitor.shared.isOffline)
					.listRowBackground(Color.clear)
				}
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.scrollEdgeEffectStyle(.soft, for: .all)
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "change-album"))
			.navigationBarTitleDisplayMode(.inline)
			.searchable(text: self.$query, prompt: String(localized: "search-albums"))
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
			}
			.toast(self.toast)
			.alert(
				self.pending.map { String(localized: "change-album-confirm \(self.track?.title ?? "") \($0.title)") } ?? "",
				isPresented: Binding(get: { self.pending != nil }, set: { if !$0 { self.pending = nil } }),
				presenting: self.pending
			) { album in
				Button(String(localized: "cancel"), role: .cancel) {}
				Button(String(localized: "move")) {
					self.move(to: album)
				}
			}
		}
		.sheetBackground()
		.task {
			guard self.track == nil, let server else { return }
			let response = try? await server.send(Library.track(id: self.trackId)) as LibraryTrackResponse
			self.track = response?.row
			// the album being looked for is usually one of the artist's
			if self.query.isEmpty, let artist = response?.row.artistName {
				self.query = artist
			}
		}
		// searches as the user types (debounced): `id` re-runs the task on every edit and cancels the previous one
		.task(id: self.query) {
			let text = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !text.isEmpty else {
				self.albums = []
				self.hasSearched = false
				return
			}
			if self.hasSearched || !self.albums.isEmpty {
				try? await Task.sleep(for: .milliseconds(400))
				guard !Task.isCancelled else { return }
			}
			await self.search(text)
		}
	}

	private func row(_ album: MediaInfo) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: album.coverArt.flatMap { URL(string: $0) })
				.frame(width: 48, height: 48)

			VStack(alignment: .leading, spacing: 2) {
				Text(album.title)
					.font(DTFont.system(16, weight: .semibold))
					.lineLimit(1)
				Text(self.details(album))
					.font(DTFont.system(13))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.lineLimit(1)
			}

			Spacer()

			if self.movingTo == album.id {
				ProgressView()
					.tint(DTColor.textPrimary)
			} else if album.id == self.track?.albumId {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.accessibilityLabel(String(localized: "current"))
			}
		}
		.contentShape(Rectangle())
	}

	private func details(_ album: MediaInfo) -> String {
		var parts = [album.artist.name]
		if let date = album.releaseDate {
			parts.append(String(Calendar(identifier: .gregorian).component(.year, from: date)))
		}
		return parts.joined(separator: " · ")
	}

	private func search(_ text: String) async {
		guard let server else { return }
		self.isSearching = true
		defer { self.isSearching = false }

		do {
			let result: SearchResult = try await server.send(Search.search(q: text, filter: .album, limit: 15))
			guard !Task.isCancelled else { return }
			self.albums = result.albums
			self.hasSearched = true
		} catch {
			guard !Task.isCancelled else { return }
			self.albums = []
			self.toast.failure(error)
		}
	}

	private func move(to album: MediaInfo) {
		guard let server, self.movingTo == nil else { return }
		self.movingTo = album.id

		Task { @MainActor in
			defer { self.movingTo = nil }
			do {
				_ = try await server.send(Library.changeAlbum(id: self.trackId, albumId: album.id)) as MediaRow
				// the Tracks and Albums lists show the new album, and the old one is gone if it was left empty
				NotificationCenter.default.post(name: .nafynLibraryChanged, object: nil)
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
