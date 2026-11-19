// Made by Lumaa

import SwiftUI
import PhotosUI
import Safyn

struct PlaylistDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var playlistId: String

	var body: some View {
		AsyncContentView(placeholder: PlaylistDetail.placeholder) {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.fetchPlaylistDetail(pid: self.playlistId)
		} content: { detail, _ in
			PlaylistDetailContent(playlistId: self.playlistId, initialDetail: detail)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct PlaylistDetailContent: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss
	@Environment(\.colorScheme) private var colorScheme
	/// Drawn as the screen's skeleton with placeholder data: nothing is fetched (DESIGN.md "Skeleton loading").
	@Environment(\.isSkeleton) private var isSkeleton

	let playlistId: String
	@State private var detail: PlaylistDetail
	@State private var paginator: Paginator<PlaylistEntry>? = nil

	@State private var toast = ToastState()
	@State private var showEdit = false
	@State private var showMembers = false
	@State private var showAddTracks = false
	@State private var showDeleteConfirm = false
	@State private var showLeaveConfirm = false
	@State private var showCoverPicker = false
	@State private var coverPickerItem: PhotosPickerItem? = nil
	@State private var showReorder = false
	/// The playlist image's dominant colours (hex), for the cover-themed screen; `nil` until read (or without image).
	@State private var imageColors: [String]? = nil

	init(playlistId: String, initialDetail: PlaylistDetail) {
		self.playlistId = playlistId
		self._detail = State(initialValue: initialDetail)
	}

	private var canReorder: Bool {
		self.detail.viewer.isOwner && self.detail.playlist.sortMode == .manual && (self.paginator?.hasMore == false) && !NetworkMonitor.shared.isOffline
	}

	/// The loaded entries in the playlist's sort order. The server only stores the mode: the order is applied here,
	/// like the web app does, so the whole playlist has to be loaded before anything but "manual" is meaningful.
	private var sortedEntries: [PlaylistEntry] {
		let items = self.paginator?.items ?? []
		switch self.detail.playlist.sortMode {
			case .title:
				return items.sorted { $0.media.title.localizedStandardCompare($1.media.title) == .orderedAscending }
			case .artist:
				return items.sorted { $0.media.artistName.localizedStandardCompare($1.media.artistName) == .orderedAscending }
			case .addedBy:
				return items.sorted { $0.addedBy.username.localizedStandardCompare($1.addedBy.username) == .orderedAscending }
			case .duration:
				return items.sorted { $0.media.duration < $1.media.duration }
			default:
				return items
		}
	}

	/// The playlist's page on the Nafyn web app (`/l/playlist/<id>`), shown for sharing once it is public.
	private var shareURL: URL? {
		guard self.detail.playlist.privacy == .public, let server else { return nil }
		return server.instance.baseURL.appending(path: "l/playlist/\(self.playlistId)")
	}

	private var coverURL: URL? {
		guard self.detail.playlist.image != nil, let server else { return nil }
		let endpoint = Playlist.image(pid: self.playlistId, token: server.authToken)
		guard var components = URLComponents(url: server.instance.baseURL, resolvingAgainstBaseURL: false) else { return nil }
		components.path += endpoint.path
		if !endpoint.queries.isEmpty {
			components.queryItems = endpoint.queries
		}
		return components.url
	}

	var body: some View {
		let palette = CoverPalette(imageColors: self.imageColors, colorScheme: self.colorScheme)

		// The same layout as an album or a track (DESIGN.md "Track/Album Detail view"): the image edge to edge with
		// the title on it, then the actions and the tracks; two panes when the window has room.
		AdaptiveCoverDetail(palette: palette) {
			self.header(palette: palette)
		} compact: {
			self.actions
			self.trackList(palette: palette)
		} primary: {
			self.details(palette: palette)
		} secondary: {
			self.actions
			self.trackList(palette: palette)
		}
		.task(id: self.detail.playlist.image) {
			guard !self.isSkeleton else { return }
			self.imageColors = await Self.hexColors(of: self.coverURL)
		}
		.task(id: "\(self.detail.playlist.sortMode)-\(self.paginator != nil)") {
			// sorting only what is scrolled into view would silently miss tracks
			guard self.detail.playlist.sortMode != .manual, let paginator = self.paginator else { return }
			while paginator.hasMore, paginator.error == nil, !Task.isCancelled {
				await paginator.loadMore()
			}
		}
		.task {
			guard !self.isSkeleton, self.paginator == nil, let server else { return }
			self.paginator = Paginator<PlaylistEntry>(
				seed: PaginatedResponse(items: self.detail.entries, page: 1, limit: max(self.detail.entries.count, 1), total: self.detail.entriesTotal, hasMore: self.detail.entriesHasMore),
				fetchPage: { page, limit in
					try await server.fetchPlaylistTracks(pid: self.playlistId, page: page, limit: limit)
				}
			)
		}
		.toast(self.toast)
		.toolbar {
			if let shareURL = self.shareURL {
				ToolbarItem(placement: .primaryAction) {
					ShareLink(item: shareURL) {
						Label(String(localized: "share"), systemImage: "square.and.arrow.up")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}

				// sharing and the rest of the actions have nothing to do with one another
				ToolbarSpacer(.fixed, placement: .primaryAction)
			}

			ToolbarOverflowMenu {
				if self.detail.viewer.isOwner {
					Button {
						self.showEdit = true
					} label: {
						Label(String(localized: "edit"), systemImage: "pencil")
					}
					.tint(Color.primary)
					.disabled(NetworkMonitor.shared.isOffline)
				}

				Button {
					self.showMembers = true
				} label: {
					Label(String(localized: "members"), systemImage: "person.2")
				}
				.tint(Color.primary)

				if self.detail.viewer.isOwner || self.detail.viewer.isMember {
					Button {
						self.showAddTracks = true
					} label: {
						Label(String(localized: "add-tracks"), systemImage: "plus")
					}
					.tint(Color.primary)
					.disabled(NetworkMonitor.shared.isOffline)
				}

				if self.canReorder {
					Button {
						self.showReorder = true
					} label: {
						Label(String(localized: "reorder"), systemImage: "arrow.up.arrow.down")
					}
					.tint(Color.primary)
				}

				if self.detail.viewer.isOwner {
					Button {
						self.showCoverPicker = true
					} label: {
						Label(String(localized: "change-image"), systemImage: "photo")
					}
					.tint(Color.primary)
					.disabled(NetworkMonitor.shared.isOffline)
				}

				PinMenuButton(target: .playlist(self.playlistId))

				Button {
					DownloadManager.shared.downloadPlaylist(id: self.playlistId, title: self.detail.playlist.title)
				} label: {
					Label(String(localized: "download-playlist"), systemImage: "arrow.down.circle")
				}
				.tint(Color.primary)
				.disabled(NetworkMonitor.shared.isOffline)

				if self.detail.viewer.isOwner {
					Button(role: .destructive) {
						self.showDeleteConfirm = true
					} label: {
						Label(String(localized: "delete"), systemImage: "trash")
					}
					.tint(Color.red)
					.disabled(NetworkMonitor.shared.isOffline)
				} else if self.detail.viewer.isMember {
					Button(role: .destructive) {
						self.showLeaveConfirm = true
					} label: {
						Label(String(localized: "leave"), systemImage: "rectangle.portrait.and.arrow.right")
					}
					.tint(Color.red)
					.disabled(NetworkMonitor.shared.isOffline)
				}
			}
		}
		// attached to the toolbar's host view: both are triggered from the toolbar menu
		.alert(String(localized: "delete-playlist-confirm"), isPresented: self.$showDeleteConfirm) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "delete"), role: .destructive) {
				self.deletePlaylist()
			}
		}
		.alert(String(localized: "leave-playlist-confirm"), isPresented: self.$showLeaveConfirm) {
			Button(String(localized: "cancel"), role: .cancel) {}
			Button(String(localized: "leave"), role: .destructive) {
				self.leavePlaylist()
			}
		}
		.sheet(isPresented: self.$showEdit) {
			PlaylistEditSheet(playlist: self.detail.playlist) { updated in
				self.detail = PlaylistDetail(playlist: updated, owner: self.detail.owner, members: self.detail.members, entries: self.detail.entries, entriesTotal: self.detail.entriesTotal, entriesHasMore: self.detail.entriesHasMore, viewer: self.detail.viewer)
			}
		}
		.sheet(isPresented: self.$showMembers) {
			PlaylistMembersSheet(playlistId: self.playlistId, owner: self.detail.owner, isOwner: self.detail.viewer.isOwner, members: self.detail.members) { updatedMembers in
				self.detail = PlaylistDetail(playlist: self.detail.playlist, owner: self.detail.owner, members: updatedMembers, entries: self.detail.entries, entriesTotal: self.detail.entriesTotal, entriesHasMore: self.detail.entriesHasMore, viewer: self.detail.viewer)
			}
		}
		.sheet(isPresented: self.$showAddTracks) {
			AddTracksToPlaylistSheet(playlistId: self.playlistId, existingMediaIds: Set(self.paginator?.items.map { $0.media.id } ?? [])) {
				Task { await self.paginator?.reset() }
			}
		}
		.sheet(isPresented: self.$showReorder) {
			if let paginator = self.paginator {
				PlaylistReorderSheet(entries: paginator.items) { from, to in
					self.moveTracks(from: from, to: to)
				}
			}
		}
		.photosPicker(isPresented: self.$showCoverPicker, selection: self.$coverPickerItem, matching: .images)
		.onChange(of: self.coverPickerItem) { _, newItem in
			guard let newItem else { return }
			Task {
				guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
				await self.uploadCover(data: data)
			}
		}
	}

	/// The playlist image's dominant colours as hex, for ``CoverPalette``.
	private static func hexColors(of url: URL?) async -> [String]? {
		guard url != nil else { return nil }
		let colors = await CoverPaletteExtractor.palette(for: url)
		return colors.compactMap { color in
			var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
			guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
			return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
		}
	}

	private func header(palette: CoverPalette) -> some View {
		CoverHeader(url: self.coverURL, palette: palette) {
			Text(self.detail.playlist.title)
				.font(DTFont.serif(31))
				.foregroundStyle(palette.primary)

			Text(self.detail.owner.displayName ?? self.detail.owner.username)
				.font(DTFont.serifItalic(20))
				.foregroundStyle(palette.primary)
		}
	}

	/// The description, and how many tracks.
	@ViewBuilder
	private func details(palette: CoverPalette) -> some View {
		if let description = self.detail.playlist.description, !description.isEmpty {
			Text(description)
				.font(DTFont.system(18))
				.foregroundStyle(palette.secondary)
		}
		Text("\(self.detail.entriesTotal) " + String(localized: "tracks"))
			.font(DTFont.system(16))
			.foregroundStyle(palette.secondary)
	}

	/// Play / Shuffle, and the sort order for those who may change it.
	@ViewBuilder
	private var actions: some View {
		HStack {
			Button {
				self.playAll(shuffle: false)
			} label: {
				Label(String(localized: "play"), systemImage: "play.fill")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())

			Button {
				self.playAll(shuffle: true)
			} label: {
				Label(String(localized: "shuffle"), systemImage: "shuffle")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
		}

		if self.detail.viewer.isOwner || self.detail.viewer.isMember {
			Picker(String(localized: "sort"), selection: Binding(get: { self.detail.playlist.sortMode }, set: { self.updateSortMode($0) })) {
				Text("manual").tag(PlaylistSortMode.manual)
				Text("title").tag(PlaylistSortMode.title)
				Text("artist").tag(PlaylistSortMode.artist)
				Text("added-by").tag(PlaylistSortMode.addedBy)
				Text("duration").tag(PlaylistSortMode.duration)
			}
			.tint(Color.primary)
			.disabled(NetworkMonitor.shared.isOffline)
			.pickerStyle(.menu)
		}
	}

	@ViewBuilder
	private func trackList(palette: CoverPalette) -> some View {
		if self.isSkeleton {
			// no paginator in a skeleton: the placeholder's own rows
			LazyVStack(spacing: 0) {
				ForEach(self.detail.entries, id: \.entryId) { entry in
					self.trackRow(entry, in: self.detail.entries)
				}
			}
		} else if let paginator {
			let entries = self.sortedEntries
			LazyVStack(spacing: 0) {
				ForEach(Array(entries.enumerated()), id: \.element.entryId) { index, entry in
					self.trackRow(entry, in: entries)
						.onAppear { paginator.loadNextPageIfNeeded(currentItem: entry) }

					if index < entries.count - 1 {
						Divider()
							.overlay(palette.secondary.opacity(0.3))
					}
				}

				if paginator.isLoadingPage {
					ProgressView()
						.tint(DTColor.textPrimary)
						.padding()
				}
			}
		}
	}

	/// A row with its cover (a playlist mixes albums); held, the actions the list's swipes used to carry.
	private func trackRow(_ entry: PlaylistEntry, in entries: [PlaylistEntry]) -> some View {
		TrackRow(coverURL: entry.media.listCoverURL, title: entry.media.title, subtitle: entry.media.artistName, duration: entry.media.duration, fileSize: entry.media.fileSize, verticalPadding: 8) {
			self.play(entry, in: entries)
		}
		.contextMenu {
			if DownloadManager.shared.isDownloaded(trackId: entry.media.id) {
				Button(role: .destructive) {
					if let download = DownloadManager.shared.downloads.first(where: { $0.id == entry.media.id }) {
						DownloadManager.shared.delete(download)
					}
				} label: {
					Label(String(localized: "remove-download"), systemImage: "arrow.down.circle.fill")
				}
				.tint(Color.red)
			} else {
				Button {
					DownloadManager.shared.downloadTrack(entry.media)
				} label: {
					Label(String(localized: "download"), systemImage: "arrow.down.circle")
				}
				.tint(Color.primary)
				.disabled(DownloadManager.shared.isDownloading(trackId: entry.media.id) || NetworkMonitor.shared.isOffline)
			}

			ExternalLinkMenuItems(item: ExternalShareItem(title: entry.media.title, artist: entry.media.artistName))

			if self.canRemove(entry) {
				Divider()

				Button(role: .destructive) {
					self.removeTrack(entry)
				} label: {
					Label(String(localized: "remove-from-playlist"), systemImage: "minus.circle")
				}
				.tint(Color.red)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
	}

	private func canRemove(_ entry: PlaylistEntry) -> Bool {
		self.detail.viewer.isOwner || entry.addedBy.id == self.detail.viewer.userId
	}

	private func play(_ entry: PlaylistEntry, in entries: [PlaylistEntry]) {
		PlaybackSource.play(entry.media, queue: entries.map { $0.media }, recordContext: RecordContext(type: .playlist, refId: self.playlistId))
	}

	private func playAll(shuffle: Bool) {
		var queue = self.sortedEntries.map({ $0.media })
		guard !queue.isEmpty else { return }
		if shuffle {
			queue.shuffle()
		}
		PlaybackSource.play(queue[0], queue: queue, recordContext: RecordContext(type: .playlist, refId: self.playlistId))
	}

	private func moveTracks(from: IndexSet, to: Int) {
		guard let paginator else { return }
		paginator.move(fromOffsets: from, toOffset: to)
		self.persistOrder(paginator.items)
	}

	private func persistOrder(_ items: [PlaylistEntry]) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Playlist.reorder(pid: self.playlistId, order: items.map { $0.entryId })) as ReorderedResponse
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func removeTrack(_ entry: PlaylistEntry) {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Playlist.removeTrack(pid: self.playlistId, eid: entry.entryId)) as RemovedResponse
				self.paginator?.remove(where: { $0.entryId == entry.entryId })
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func updateSortMode(_ mode: PlaylistSortMode) {
		guard let server else { return }
		let previous = self.detail.playlist
		self.detail = PlaylistDetail(playlist: PlaylistRow(id: previous.id, ownerId: previous.ownerId, title: previous.title, description: previous.description, privacy: previous.privacy, image: previous.image, sortMode: mode, createdAt: previous.createdAt, updatedAt: previous.updatedAt), owner: self.detail.owner, members: self.detail.members, entries: self.detail.entries, entriesTotal: self.detail.entriesTotal, entriesHasMore: self.detail.entriesHasMore, viewer: self.detail.viewer)

		Task {
			do {
				_ = try await server.send(Playlist.update(pid: self.playlistId, sortMode: mode)) as PlaylistRow
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func uploadCover(data: Data) async {
		guard let server else { return }
		do {
			let updated = try await server.send(Playlist.setImage(pid: self.playlistId, data: data, filename: "cover.jpg", mimeType: "image/jpeg")) as PlaylistRow
			self.detail = PlaylistDetail(playlist: updated, owner: self.detail.owner, members: self.detail.members, entries: self.detail.entries, entriesTotal: self.detail.entriesTotal, entriesHasMore: self.detail.entriesHasMore, viewer: self.detail.viewer)
		} catch {
			self.toast.failure(error)
		}
	}

	private func deletePlaylist() {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Playlist.delete(pid: self.playlistId)) as RemovedResponse
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}

	private func leavePlaylist() {
		guard let server else { return }
		Task {
			do {
				_ = try await server.send(Playlist.leave(pid: self.playlistId)) as RemovedResponse
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

/// Reordering a manual playlist by dragging (the screen itself is no `List`, so it has no edit mode).
private struct PlaylistReorderSheet: View {
	@Environment(\.dismiss) private var dismiss

	@State var entries: [PlaylistEntry]
	let onMove: (IndexSet, Int) -> Void

	var body: some View {
		NavigationStack {
			List {
				ForEach(self.entries, id: \.entryId) { entry in
					TrackRow(coverURL: entry.media.listCoverURL, title: entry.media.title, subtitle: entry.media.artistName, duration: entry.media.duration)
						.listRowBackground(Color.clear)
				}
				.onMove { from, to in
					self.entries.move(fromOffsets: from, toOffset: to)
					self.onMove(from, to)
				}
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.environment(\.editMode, .constant(.active))
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "reorder"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "done"), systemImage: "checkmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}
		}
		.sheetBackground()
	}
}
