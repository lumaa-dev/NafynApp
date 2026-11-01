// Made by Lumaa

import SwiftUI
import PhotosUI
import Safyn

struct PlaylistDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var playlistId: String

	var body: some View {
		AsyncContentView {
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
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

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

	init(playlistId: String, initialDetail: PlaylistDetail) {
		self.playlistId = playlistId
		self._detail = State(initialValue: initialDetail)
	}

	private var canReorder: Bool {
		self.detail.viewer.isOwner && self.detail.playlist.sortMode == .manual && (self.paginator?.hasMore == false) && !NetworkMonitor.shared.isOffline
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
		self.content
		.task {
			guard self.paginator == nil, let server else { return }
			self.paginator = Paginator<PlaylistEntry>(
				seed: PaginatedResponse(items: self.detail.entries, page: 1, limit: max(self.detail.entries.count, 1), total: self.detail.entriesTotal, hasMore: self.detail.entriesHasMore),
				fetchPage: { page, limit in
					try await server.fetchPlaylistTracks(pid: self.playlistId, page: page, limit: limit)
				}
			)
		}
		.background(DTColor.background.ignoresSafeArea())
		.toast(self.toast)
		.navigationTitle(self.detail.playlist.title)
		.toolbar {
			if let shareURL = self.shareURL {
				ToolbarItem(placement: .primaryAction) {
					ShareLink(item: shareURL) {
						Label(String(localized: "share"), systemImage: "square.and.arrow.up")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}
			}

			ToolbarItem(placement: .primaryAction) {
				Menu {
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
						.tint(DTColor.buttonDanger)
						.disabled(NetworkMonitor.shared.isOffline)
					} else if self.detail.viewer.isMember {
						Button(role: .destructive) {
							self.showLeaveConfirm = true
						} label: {
							Label(String(localized: "leave"), systemImage: "rectangle.portrait.and.arrow.right")
						}
						.tint(DTColor.buttonDanger)
						.disabled(NetworkMonitor.shared.isOffline)
					}
				} label: {
					Label(String(localized: "more"), systemImage: "ellipsis")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
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
		.photosPicker(isPresented: self.$showCoverPicker, selection: self.$coverPickerItem, matching: .images)
		.onChange(of: self.coverPickerItem) { _, newItem in
			guard let newItem else { return }
			Task {
				guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
				await self.uploadCover(data: data)
			}
		}
	}

	/// Compact: one list with the header as its first row. Regular width (Duo inner display, iPad): the
	/// header in one pane and the tracks in a list of their own beside it.
	@ViewBuilder
	private var content: some View {
		if DTLayout.hasRoomForPanes(horizontal: self.horizontalSizeClass, vertical: self.verticalSizeClass) {
			SplitPanes(fallbackPrimaryWidth: DTLayout.detailCoverWidth(horizontal: .regular, vertical: .regular) + 40) {
				PaneScroll { self.header }
			} secondary: {
				self.styled(List { self.rows })
			}
		} else {
			self.styled(
				List {
					Section {
						self.header
					}
					.listRowInsets(EdgeInsets())
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)

					self.rows
				}
			)
			.contentColumn()
			.padding(.horizontal)
		}
	}

	private func styled<Content: View>(_ list: Content) -> some View {
		list
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.scrollEdgeEffectStyle(.soft, for: .all)
	}

	@ViewBuilder
	private var rows: some View {
		if let paginator {
			if self.canReorder {
				self.trackRows(for: paginator)
					.onMove(perform: self.moveTracks)
			} else {
				self.trackRows(for: paginator)
			}
		}
	}

	private func trackRows(for paginator: Paginator<PlaylistEntry>) -> some DynamicViewContent {
		ForEach(paginator.items) { entry in
			TrackRow(coverURL: entry.media.coverArt.flatMap { URL(string: $0) }, title: entry.media.title, subtitle: entry.media.artistName, duration: entry.media.duration, fileSize: entry.media.fileSize) {
				self.play(entry, in: paginator.items)
			}
			.listRowBackground(Color.clear)
			.onAppear { paginator.loadNextPageIfNeeded(currentItem: entry) }
			.swipeActions(edge: .leading) {
				if DownloadManager.shared.isDownloaded(trackId: entry.media.id) {
					Button {
						if let download = DownloadManager.shared.downloads.first(where: { $0.id == entry.media.id }) {
							DownloadManager.shared.delete(download)
						}
					} label: {
						Label(String(localized: "remove"), systemImage: "arrow.down.circle.fill")
					}
					.tint(DTColor.textPrimary.opacity(0.4))
				} else {
					Button {
						DownloadManager.shared.downloadTrack(entry.media)
					} label: {
						Label(String(localized: "download"), systemImage: "arrow.down.circle")
					}
					.tint(DTColor.accentStart)
					.disabled(DownloadManager.shared.isDownloading(trackId: entry.media.id) || NetworkMonitor.shared.isOffline)
				}
			}
			.swipeActions(edge: .trailing) {
				if self.canRemove(entry) {
					Button(role: .destructive) {
						self.removeTrack(entry)
					} label: {
						Label(String(localized: "remove"), systemImage: "trash")
					}
					.tint(DTColor.buttonDanger)
					.disabled(NetworkMonitor.shared.isOffline)
				}
			}
		}
	}

	@ViewBuilder
	private var header: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .top, spacing: 16) {
				Button {
					self.showCoverPicker = true
				} label: {
					CoverImage(url: self.coverURL)
						.frame(width: 120, height: 120)
				}
				.buttonStyle(.plain)
				.disabled(!self.detail.viewer.isOwner || NetworkMonitor.shared.isOffline)

				VStack(alignment: .leading, spacing: 4) {
					Text(self.detail.playlist.title)
						.font(DTFont.serif(27))
						.foregroundStyle(DTColor.textPrimary)

					if let description = self.detail.playlist.description, !description.isEmpty {
						Text(description)
							.font(DTFont.system(16))
							.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					}

					Text(self.detail.owner.displayName ?? self.detail.owner.username)
						.font(DTFont.system(15))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				}

				Spacer()
			}

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
				.disabled(NetworkMonitor.shared.isOffline)
				.pickerStyle(.menu)
			}
		}
		.padding(.vertical, 8)
	}

	private func canRemove(_ entry: PlaylistEntry) -> Bool {
		self.detail.viewer.isOwner || entry.addedBy.id == self.detail.viewer.userId
	}

	private func play(_ entry: PlaylistEntry, in entries: [PlaylistEntry]) {
		PlaybackSource.play(entry.media, queue: entries.map { $0.media }, recordContext: RecordContext(type: .playlist, refId: self.playlistId))
	}

	private func playAll(shuffle: Bool) {
		guard var queue = self.paginator?.items.map({ $0.media }), !queue.isEmpty else { return }
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
				await self.paginator?.reset()
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
