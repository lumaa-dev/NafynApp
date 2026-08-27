// Made by Lumaa

import SwiftUI
import MusicKit
import Safyn

/// Imports one Apple Music library playlist as Nafyn download requests.
///
/// `MusicKit` and `Safyn` both declare `Playlist`, `Track`, and `Request` types, so every reference to
/// one of those needs an explicit module prefix in this file to disambiguate.
///
/// Flow: (1) resolve every track's ISRC via `MusicKit`, splitting into a matched-ISRC list and a
/// missing-ISRC list; (2) look each ISRC up against the Nafyn server with `Safyn.Track.getByIsrc`; (3)
/// file a `Safyn.Request.create` for every track that resolved. Tracks with no ISRC can't be matched
/// server-side, so they're collected separately and shown to the user instead of silently dropped.
struct AppleMusicImportSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.server) private var server: NafynServer?

	private enum Phase {
		case loadingPlaylists
		case pickingPlaylist([MusicKit.Playlist])
		case importing(step: ImportStep, progress: Double, total: Double)
		case missingIsrc([MissingTrack])
		case finished(importedCount: Int)
		case failed(String)
	}

	private enum ImportStep {
		case fetchingIsrc
		case fetchingSongs
		case creatingRequests

		var message: String {
			switch self {
				case .fetchingIsrc: return String(localized: "import-step-fetch-isrc")
				case .fetchingSongs: return String(localized: "import-step-fetch-songs")
				case .creatingRequests: return String(localized: "import-step-create-requests")
			}
		}
	}

	private struct MissingTrack: Identifiable {
		let id = UUID()
		let title: String
		let artist: String
	}

	@State private var phase: Phase = .loadingPlaylists

	var body: some View {
		NavigationStack {
			Group {
				switch self.phase {
					case .loadingPlaylists:
						List {
							SkeletonTrackRows(showsCover: false)
						}
						.listStyle(.plain)

					case .pickingPlaylist(let playlists):
						self.playlistPicker(playlists)

					case .importing(let step, let progress, let total):
						self.importProgress(step: step, progress: progress, total: total)

					case .missingIsrc(let tracks):
						self.missingIsrcList(tracks)

					case .finished(let count):
						self.finishedView(count: count)

					case .failed(let message):
						self.failedView(message)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "import-apple-music"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String(localized: "close")) {
						self.dismiss()
					}
					.tint(Color.primary)
				}
			}
		}
		.interactiveDismissDisabled()
		.task {
			await self.loadPlaylists()
		}
	}

	@ViewBuilder
	private func playlistPicker(_ playlists: [MusicKit.Playlist]) -> some View {
		if playlists.isEmpty {
			ContentUnavailableView(String(localized: "no-playlists"), systemImage: "music.note.list")
		} else {
			List(playlists) { playlist in
				Button {
					Task {
						await self.startImport(playlist: playlist)
					}
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(playlist.name)
							.foregroundStyle(DTColor.textPrimary)

						if let count = playlist.tracks?.count {
							Text("\(count)")
								.font(.footnote)
								.foregroundStyle(DTColor.textPrimary.opacity(0.55))
						}
					}
				}
				.tint(Color.primary)
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
		}
	}

	@ViewBuilder
	private func importProgress(step: ImportStep, progress: Double, total: Double) -> some View {
		VStack(spacing: 16) {
			Spacer()

			ProgressView(value: progress, total: max(total, 1))
				.progressViewStyle(.linear)
				.padding(.horizontal, 32)

			Text(step.message)
				.font(.footnote)
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			Spacer()
		}
	}

	@ViewBuilder
	private func missingIsrcList(_ tracks: [MissingTrack]) -> some View {
		List {
			Section {
				Text(String(localized: "error-import-isrc"))
					.foregroundStyle(DTColor.buttonDanger)
			}

			Section {
				ForEach(tracks) { track in
					VStack(alignment: .leading, spacing: 2) {
						Text(track.title)
							.foregroundStyle(DTColor.textPrimary)
						Text(track.artist)
							.font(.footnote)
							.foregroundStyle(DTColor.textPrimary.opacity(0.55))
					}
				}
			}
		}
		.scrollContentBackground(.hidden)
	}

	@ViewBuilder
	private func finishedView(count: Int) -> some View {
		ContentUnavailableView(
			String(localized: "import-complete"),
			systemImage: "checkmark.circle",
			description: Text("\(count)")
		)
	}

	@ViewBuilder
	private func failedView(_ message: String) -> some View {
		ContentUnavailableView(
			String(localized: "error"),
			systemImage: "exclamationmark.triangle",
			description: Text(message)
		)
	}

	private func loadPlaylists() async {
		let status = await MusicAuthorization.request()
		guard status == .authorized else {
			self.phase = .failed(String(localized: "error-apple-music-denied"))
			return
		}

		do {
			let request = MusicLibraryRequest<MusicKit.Playlist>()
			let response = try await request.response()
			self.phase = .pickingPlaylist(Array(response.items))
		} catch {
			self.phase = .failed(error.localizedDescription)
		}
	}

	private func startImport(playlist: MusicKit.Playlist) async {
		guard let server else {
			self.phase = .failed(String(localized: "error-unauthenticated"))
			return
		}

		do {
			// Step 1: resolve every track's ISRC, splitting matched from missing.
			self.phase = .importing(step: .fetchingIsrc, progress: 0, total: 1)
			let detailedPlaylist = try await playlist.with(.tracks)
			let tracks: [MusicKit.Track] = detailedPlaylist.tracks.map { Array($0) } ?? []

			var isrcs: [String] = []
			var missing: [MissingTrack] = []

			for (index, track) in tracks.enumerated() {
				switch track {
					case .song(let song):
						// Library `Song`s frequently have `isrc == nil` — it's populated reliably on the
						// catalog copy, so look that up by ID (`SongFilter.id`, shared between a library
						// item and its catalog counterpart when it was matched from Apple Music).
						let catalogSong = try? await MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: song.id).response().items.first
//						print("[startImport+forLoop] Fetched song data \(catalogSong?.title ?? "NO TITLE FOUND???????")")
						if let isrc = catalogSong?.isrc {
							isrcs.append(isrc)
						} else {
							missing.append(MissingTrack(title: song.title, artist: song.artistName))
						}
					case .musicVideo(let video):
						missing.append(MissingTrack(title: video.title, artist: video.artistName))
					@unknown default:
						break
				}

				self.phase = .importing(step: .fetchingIsrc, progress: Double(index + 1), total: Double(tracks.count))
			}

			// Step 2: turn each ISRC into Nafyn track data.
			var converted: [TrackDetail] = []
			for (index, isrc) in isrcs.enumerated() {
				self.phase = .importing(step: .fetchingSongs, progress: Double(index), total: Double(max(isrcs.count, 1)))
				if let detail: TrackDetail = try? await server.send(Safyn.Track.getByIsrc(isrc: isrc)) {
					converted.append(detail)
				}
			}

			// Step 3: file a download request for each resolved track.
			var importedCount = 0
			for (index, detail) in converted.enumerated() {
				self.phase = .importing(step: .creatingRequests, progress: Double(index), total: Double(max(converted.count, 1)))
				if let _: NafynRequest = try? await server.send(Safyn.Request.create(id: detail.info.id, type: .track)) {
					importedCount += 1
				}
			}

			if !missing.isEmpty {
				self.phase = .missingIsrc(missing)
			} else {
				self.phase = .finished(importedCount: importedCount)
			}
		} catch {
			self.phase = .failed(error.localizedDescription)
		}
	}
}
