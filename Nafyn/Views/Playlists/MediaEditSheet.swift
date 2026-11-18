// Made by Lumaa

import SwiftUI
import PhotosUI
import Safyn

/// Edits a library track's metadata, or several tracks at once (an album, a selection): the iOS side of the web app's
/// `MediaEditModal.vue`. One track shows every field; several show only what they share (artist, album, type, date,
/// label, cover) and only the fields changed are sent. The cover is picked from the album's other releases
/// (`Library.coverOptions`) or uploaded from Photos (`Library.setCover`); an uploaded cover can be removed again.
struct MediaEditSheet: View {
	@Environment(\.server) private var server: NafynServer?
	@Environment(\.dismiss) private var dismiss

	let trackIds: [String]

	@State private var tracks: [MediaRow] = []
	@State private var loadError: Error?
	@State private var isSaving = false
	@State private var toast = ToastState()

	// the form, starting from the first track (for several: from what they all share)
	@State private var title = ""
	@State private var artist = ""
	@State private var album = ""
	@State private var albumType: AlbumKind? = nil
	@State private var trackNumber = ""
	@State private var hasReleaseDate = false
	@State private var releaseDate = Date()
	@State private var label = ""

	// the cover: one picked from the archive, or a picture to upload, or the uploaded one removed
	@State private var coverOptions: [CoverOption] = []
	@State private var pickedCover: CoverOption?
	@State private var photoItem: PhotosPickerItem?
	@State private var uploadData: Data?
	@State private var removeUploaded = false

	/// What the form started from, to send only what changed.
	@State private var original: Snapshot?

	private struct Snapshot: Equatable {
		var title: String, artist: String, album: String, albumType: AlbumKind?, trackNumber: String, hasReleaseDate: Bool, releaseDate: Date, label: String
	}

	private var isBulk: Bool { self.trackIds.count > 1 }

	var body: some View {
		NavigationStack {
			Group {
				if !self.tracks.isEmpty {
					self.form
				} else if let loadError {
					ContentUnavailableView(String(localized: "error"), systemImage: "exclamationmark.triangle", description: Text(loadError.localizedDescription))
				} else {
					ProgressView()
						.tint(DTColor.textPrimary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(self.isBulk ? String(localized: "edit-tracks \(self.trackIds.count)") : String(localized: "edit-metadata"))
			.navigationBarTitleDisplayMode(.inline)
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
					if self.isSaving {
						ProgressView()
							.tint(DTColor.textPrimary)
					} else {
						Button {
							self.save()
						} label: {
							Label(String(localized: "save"), systemImage: "checkmark")
								.labelStyle(.iconOnly)
						}
						.tint(Color.primary)
						.disabled(self.tracks.isEmpty || !self.hasChanges || NetworkMonitor.shared.isOffline)
					}
				}
			}
			.toast(self.toast)
			.task { await self.load() }
			.onChange(of: self.photoItem) { _, item in
				guard let item else { return }
				Task {
					guard let data = try? await item.loadTransferable(type: Data.self),
						  let image = UIImage(data: data),
						  let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
					self.uploadData = jpeg
					self.pickedCover = nil
					self.removeUploaded = false
				}
			}
		}
		.sheetBackground()
	}

	private var form: some View {
		Form {
			Section {
				self.coverPreview
					.frame(width: 140, height: 140)
					.frame(maxWidth: .infinity)
					.listRowBackground(Color.clear)

				PhotosPicker(selection: self.$photoItem, matching: .images) {
					Label(String(localized: "upload-cover"), systemImage: "photo")
						.foregroundStyle(Color.primary)
				}
				.tint(Color.primary)

				if self.tracks.contains(where: \.hasUploadedCover), self.uploadData == nil, self.pickedCover == nil {
					Toggle(String(localized: "remove-uploaded-cover"), isOn: self.$removeUploaded)
						.tint(DTColor.dangerText)
				}

				if !self.coverOptions.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						LazyHStack(spacing: 10) {
							ForEach(self.coverOptions, id: \.id) { option in
								Button {
									self.pickedCover = option
									self.uploadData = nil
									self.photoItem = nil
									self.removeUploaded = false
								} label: {
									CoverImage(url: option.url.coverArtURL(size: 250))
										.frame(width: 72, height: 72)
										.overlay {
											if self.pickedCover?.id == option.id {
												RoundedRectangle(cornerRadius: 10).strokeBorder(DTColor.textPrimary, lineWidth: 3)
											}
										}
								}
								.buttonStyle(.plain)
								.accessibilityLabel(option.details.map { "\(option.title), \($0)" } ?? option.title)
								.accessibilityAddTraits(self.pickedCover?.id == option.id ? .isSelected : [])
							}
						}
						.padding(.vertical, 4)
					}
					.listRowBackground(Color.clear)
				}
			} header: {
				Text("cover-art")
			}
			.sheetRows()

			Section {
				if !self.isBulk {
					TextField(String(localized: "title"), text: self.$title)
				}
				TextField(String(localized: "artist"), text: self.$artist)
				TextField(String(localized: "album"), text: self.$album)
				Picker(String(localized: "album-type"), selection: self.$albumType) {
					Text("album-type-none").tag(AlbumKind?.none)
					Text("album").tag(AlbumKind?.some(.album))
					Text("ep").tag(AlbumKind?.some(.ep))
				}
				.tint(Color.primary)
				if !self.isBulk {
					TextField(String(localized: "track-number"), text: self.$trackNumber)
						.keyboardType(.numberPad)
				}
				Toggle(String(localized: "release-date"), isOn: self.$hasReleaseDate)
					.tint(DTColor.statusSuccess)
				if self.hasReleaseDate {
					DatePicker(String(localized: "release-date"), selection: self.$releaseDate, displayedComponents: .date)
						.labelsHidden()
				}
				TextField(String(localized: "record-label"), text: self.$label)
			}
			.sheetRows()
		}
		.scrollContentBackground(.hidden)
	}

	@ViewBuilder
	private var coverPreview: some View {
		if let uploadData, let image = UIImage(data: uploadData) {
			Image(uiImage: image)
				.resizable()
				.aspectRatio(1, contentMode: .fill)
				.clipShape(RoundedRectangle(cornerRadius: 12))
		} else if let pickedCover {
			CoverImage(url: pickedCover.url.coverArtURL(size: 500), cornerRadius: 12)
		} else if let first = self.tracks.first {
			CoverImage(url: self.removeUploaded ? first.coverArt?.coverArtURL(size: 500) : first.setCoverSize(500), cornerRadius: 12)
		}
	}

	private var current: Snapshot {
		Snapshot(title: self.title, artist: self.artist, album: self.album, albumType: self.albumType, trackNumber: self.trackNumber, hasReleaseDate: self.hasReleaseDate, releaseDate: self.releaseDate, label: self.label)
	}

	private var hasChanges: Bool {
		self.current != self.original || self.pickedCover != nil || self.uploadData != nil || self.removeUploaded
	}

	// MARK: - Loading

	private func load() async {
		guard self.tracks.isEmpty, let server else { return }
		do {
			let rows = try await withThrowingTaskGroup(of: (Int, MediaRow).self) { group in
				for (index, id) in self.trackIds.enumerated() {
					group.addTask { (index, (try await server.send(Library.track(id: id)) as LibraryTrackResponse).row) }
				}
				var rows: [(Int, MediaRow)] = []
				for try await row in group { rows.append(row) }
				return rows.sorted { $0.0 < $1.0 }.map(\.1)
			}
			self.fill(from: rows)
			self.tracks = rows
			await self.loadCoverOptions(rows)
		} catch {
			self.loadError = error
		}
	}

	/// The first track's values; for several, a field the tracks don't share starts empty.
	private func fill(from rows: [MediaRow]) {
		guard let first = rows.first else { return }
		func shared<T: Equatable>(_ value: (MediaRow) -> T) -> T? {
			let first = value(first)
			return rows.allSatisfy { value($0) == first } ? first : nil
		}
		self.title = first.title
		self.artist = shared(\.artistName) ?? ""
		self.album = shared { $0.album ?? "" } ?? ""
		self.albumType = shared(\.albumType) ?? nil
		self.trackNumber = first.trackNumber.map { String(Int($0)) } ?? ""
		if let date = shared(\.releaseDate) ?? nil {
			self.hasReleaseDate = true
			self.releaseDate = Date(timeIntervalSince1970: TimeInterval(date))
		}
		self.label = shared { $0.label ?? "" } ?? ""
		self.original = self.current
	}

	private func loadCoverOptions(_ rows: [MediaRow]) async {
		guard let server, let first = rows.first else { return }
		// one track: every release of its recording; several: the album's releases
		let endpoint: Library = rows.count == 1 && !first.musicbrainzId.isEmpty
			? .coverOptionsForRecording(recordingId: first.musicbrainzId)
			: .coverOptions(albumId: first.albumId)
		self.coverOptions = (try? await server.send(endpoint) as CoverOptionsResponse)?.options ?? []
	}

	// MARK: - Saving

	private func save() {
		guard let server, let original, !self.isSaving else { return }
		self.isSaving = true
		let edit = self.current
		let ids = self.tracks.map(\.id)
		let isBulk = self.isBulk

		func text(_ value: String) -> String? {
			let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty ? nil : trimmed
		}
		func patch(_ value: String) -> Patchable<String> {
			text(value).map { .value($0) } ?? .clear
		}

		let title: String? = !isBulk && edit.title != original.title ? text(edit.title) : nil
		let artist: String? = edit.artist != original.artist ? text(edit.artist) : nil
		let album: Patchable<String> = edit.album != original.album ? patch(edit.album) : .unset
		let albumType: Patchable<AlbumKind> = edit.albumType != original.albumType ? (edit.albumType.map { .value($0) } ?? .clear) : .unset
		let trackNumber: Patchable<Double> = !isBulk && edit.trackNumber != original.trackNumber ? (Double(edit.trackNumber).map { .value($0) } ?? .clear) : .unset
		let releaseDate: Patchable<Double> = edit.hasReleaseDate != original.hasReleaseDate || (edit.hasReleaseDate && edit.releaseDate != original.releaseDate)
			? (edit.hasReleaseDate ? .value(edit.releaseDate.timeIntervalSince1970.rounded()) : .clear)
			: .unset
		let label: Patchable<String> = edit.label != original.label ? patch(edit.label) : .unset
		let coverArt: Patchable<String> = self.pickedCover.map { .value($0.url) } ?? .unset
		let upload = self.uploadData
		// a picked archive cover replaces an uploaded one, which would otherwise outrank it
		let dropUploaded = self.removeUploaded || self.pickedCover != nil

		Task {
			defer { self.isSaving = false }
			do {
				for id in ids {
					_ = try await server.send(Library.editMetadata(id: id, title: title, artistName: artist, album: album, albumType: albumType, releaseDate: releaseDate, label: label, trackNumber: trackNumber, coverArt: coverArt)) as MediaRow
					if let upload {
						_ = try await server.send(Library.setCover(id: id, data: upload)) as MediaRow
					} else if dropUploaded, self.tracks.first(where: { $0.id == id })?.hasUploadedCover == true {
						_ = try await server.sendRaw(Library.deleteCover(id: id))
					}
				}
				NotificationCenter.default.post(name: .nafynLibraryChanged, object: nil)
				Haptics.success()
				self.dismiss()
			} catch {
				self.toast.failure(error)
			}
		}
	}
}
