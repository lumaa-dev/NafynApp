// Made by Lumaa

import SwiftUI
import MusicKit
import Safyn

/// Imports one Apple Music library playlist as Nafyn download requests.
///
/// `MusicKit` and `Safyn` both declare `Playlist`, `Track`, and `Request` types, so every reference to
/// one of those needs an explicit module prefix in this file to disambiguate.
///
/// Flow: (1) resolve an ISRC for every track where possible (see ``resolveISRCs(for:)`` for the fallback
/// chain); (2) ask the user whether to create one request per track; (3) for each track, look it up on the Nafyn server
/// with `Safyn.Track.getByIsrc` (title + artist fallback when the ISRC is unknown or unmatched) and file a `Safyn.Request.create`, pausing 2–4 s between requests so the
/// server's Soulseek downloads aren't rate limited. Tracks that couldn't be identified or matched are
/// listed at the end instead of silently dropped.
struct AppleMusicImportSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.server) private var server: NafynServer?

	private enum Phase {
		case loadingPlaylists
		case pickingPlaylist([MusicKit.Playlist])
		/// Busy: fetching ISRCs or creating requests. The close button is disabled while in this phase.
		case importing(step: ImportStep, progress: Double, total: Double)
		case confirming(ImportPlan)
		case report(created: Int, notImported: [MissingTrack])
		case failed(String)
	}

	private enum ImportStep {
		case fetchingIsrc
		case searchingThirdParty
		case creatingRequests

		var message: String {
			switch self {
				case .fetchingIsrc: return String(localized: "import-step-fetch-isrc")
				case .searchingThirdParty: return String(localized: "import-step-thirdparty")
				case .creatingRequests: return String(localized: "import-step-create-requests")
			}
		}
	}

	private struct ImportPlan {
		let entries: [ISRCEntry]
		let missing: [MissingTrack]
	}

	private struct MissingTrack: Identifiable {
		let id = UUID()
		let title: String
		let artist: String
	}

	/// What Nafyn looks up for one track: its ISRC when one was found (`nil` otherwise: the server then
	/// searches by title + artist only), plus the track's name so a failed lookup can still be reported.
	private struct ISRCEntry: Sendable {
		let isrc: String?
		let title: String
		let artist: String
	}

	/// One playlist track, with whatever identifiers the sources so far gave us.
	private struct Candidate: Sendable {
		var title: String
		var artist: String
		var duration: TimeInterval?
		var isrc: String?
		var catalogId: String?
	}

	private var isBusy: Bool {
		if case .importing = self.phase { return true }
		return false
	}

	/// `Track.getByIsrc` needs an ISRC in its path. For tracks without one this well-formed, unassigned code
	/// matches no recording, so the server goes straight to its `title` + `artist` fallback search.
	private static let placeholderISRC = "ZZZZZ0000000"

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

					case .confirming(let plan):
						self.confirmView(plan)

					case .report(let created, let notImported):
						self.reportView(created: created, notImported: notImported)

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
					Button {
						self.dismiss()
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "close"))
					.tint(Color.primary)
					.disabled(self.isBusy)
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
				.disabled(NetworkMonitor.shared.isOffline)
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
		}
	}

	@ViewBuilder
	private func importProgress(step: ImportStep, progress: Double, total: Double) -> some View {
		VStack(spacing: 16) {
			Spacer()

			ProgressView(value: min(progress, max(total, 1)), total: max(total, 1))
				.progressViewStyle(.linear)
				.tint(DTColor.textPrimary)
				.padding(.horizontal, 32)

			if step == .creatingRequests {
				Text("\(Int(progress)) / \(Int(total))")
					.font(DTFont.system(17).monospacedDigit())
					.foregroundStyle(DTColor.textPrimary)
			}

			Text(step.message)
				.font(.footnote)
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))

			Spacer()
		}
	}

	@ViewBuilder
	private func confirmView(_ plan: ImportPlan) -> some View {
		VStack(spacing: 20) {
			Spacer()

			Image(systemName: "tray.and.arrow.down")
				.font(.largeTitle)
				.foregroundStyle(DTColor.textPrimary)

			Text("import-confirm-title \(plan.entries.count)")
				.font(DTFont.serif(27))
				.foregroundStyle(DTColor.textPrimary)
				.multilineTextAlignment(.center)

			if !plan.missing.isEmpty {
				Text("import-confirm-missing \(plan.missing.count)")
					.font(.footnote)
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
					.multilineTextAlignment(.center)
			}

			Spacer()

			VStack(spacing: 12) {
				Button {
					Task { await self.createRequests(plan) }
				} label: {
					Text("import-confirm-create")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.filled())
				.disabled(NetworkMonitor.shared.isOffline)

				Button {
					self.dismiss()
				} label: {
					Text("import-confirm-decline")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.hollow())
			}
		}
		.padding()
	}

	@ViewBuilder
	private func reportView(created: Int, notImported: [MissingTrack]) -> some View {
		if notImported.isEmpty {
			ContentUnavailableView(
				String(localized: "import-complete"),
				systemImage: "checkmark.circle",
				description: Text("\(created)")
			)
		} else {
			List {
				Section {
					Label {
						Text("\(created)")
					} icon: {
						Image(systemName: "checkmark.circle")
					}
					.foregroundStyle(DTColor.textPrimary)
				} header: {
					Text("import-complete")
				}

				Section {
					ForEach(notImported) { track in
						VStack(alignment: .leading, spacing: 2) {
							Text(track.title)
								.foregroundStyle(DTColor.textPrimary)
							Text(track.artist)
								.font(.footnote)
								.foregroundStyle(DTColor.textPrimary.opacity(0.55))
						}
					}
				} header: {
					Text("import-not-imported")
				}
			}
			.scrollContentBackground(.hidden)
		}
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

	/// Fetches every track's ISRC, then waits on the confirmation screen — nothing is requested yet.
	private func startImport(playlist: MusicKit.Playlist) async {
		guard server != nil else {
			self.phase = .failed(String(localized: "error-unauthenticated"))
			return
		}

		self.phase = .importing(step: .fetchingIsrc, progress: 0, total: 1)
		let (entries, missing) = await self.resolveISRCs(for: playlist)

		if entries.isEmpty {
			self.phase = .failed(String(localized: "error-import-no-matches"))
		} else {
			self.phase = .confirming(ImportPlan(entries: entries, missing: missing))
		}
	}

	/// One Nafyn lookup + request per ISRC, `2...4` seconds apart: the server hands requests to Soulseek,
	/// which rate limits bursts of searches/downloads.
	private func createRequests(_ plan: ImportPlan) async {
		guard let server else {
			self.phase = .failed(String(localized: "error-unauthenticated"))
			return
		}

		let total = Double(plan.entries.count)
		var created = 0
		var notImported = plan.missing

		self.phase = .importing(step: .creatingRequests, progress: 0, total: total)
		for (index, entry) in plan.entries.enumerated() {
			var didCreate = false
			if let detail: TrackDetail = try? await server.send(Safyn.Track.getByIsrc(isrc: entry.isrc ?? Self.placeholderISRC, title: entry.title, artist: entry.artist)) {
				if detail.info.inLibrary == true || detail.requested == true {
					// already on this account: nothing to request, nothing missing
				} else if let _: NafynRequest = try? await server.send(Safyn.Request.create(id: detail.info.id, type: .track)) {
					created += 1
					didCreate = true
				} else {
					notImported.append(MissingTrack(title: entry.title, artist: entry.artist))
				}
			} else {
				notImported.append(MissingTrack(title: entry.title, artist: entry.artist))
			}

			self.phase = .importing(step: .creatingRequests, progress: Double(index + 1), total: total)

			if didCreate, index < plan.entries.count - 1 {
				try? await Task.sleep(for: .seconds(Double.random(in: 2...4)))
			}
		}

		self.phase = .report(created: created, notImported: notImported)
	}

	// MARK: - ISRC resolution

	/// Resolves an ISRC per track, cheapest and most accurate source first; each stage only handles what the
	/// previous ones couldn't:
	/// 1. Apple Music API `GET /v1/me/library/playlists/{id}/tracks?include=catalog` through `MusicDataRequest`
	///    — returns each library track *with its catalog counterpart attached*, ISRC included, in one paged
	///    call. This is what was missing: `Song.isrc` is nil on library songs, and per-song lookups can't
	///    map a library ID to the catalog. (Fallback if that request fails: the MusicKit `Song`s themselves.)
	/// 2. Batched catalog lookup by catalog ID, for tracks that had an ID but no ISRC attached.
	/// 3. Apple Music catalog text search, with fuzzy title/artist matching.
	/// 4. Last resort, third party: Deezer's public API (search, then track → ISRC). Sends title + artist only.
	private func resolveISRCs(for playlist: MusicKit.Playlist) async -> (entries: [ISRCEntry], missing: [MissingTrack]) {
		var candidates: [Candidate]
		var missing: [MissingTrack] = []

		do {
			candidates = try await Self.libraryCandidates(of: playlist.id)
		} catch {
			print("[AppleMusicImport] library tracks request failed, falling back to MusicKit songs: \(error)")
			candidates = []
			if let tracks = try? await Self.allTracks(of: playlist) {
				for track in tracks {
					switch track {
						case .song(let song):
							candidates.append(Candidate(title: song.title, artist: song.artistName, duration: song.duration, isrc: song.isrc, catalogId: Self.catalogID(of: song)))
						case .musicVideo(let video):
							missing.append(MissingTrack(title: video.title, artist: video.artistName))
						@unknown default:
							break
					}
				}
			}
		}

		let total = Double(max(candidates.count, 1))
		func handled() -> Double { Double(candidates.filter { $0.isrc != nil }.count) }
		self.phase = .importing(step: .fetchingIsrc, progress: handled(), total: total)

		// 2. Batched catalog lookup by ID.
		let needLookup = candidates.indices.filter { candidates[$0].isrc == nil && candidates[$0].catalogId != nil }
		let uniqueIds = Array(Set(needLookup.compactMap { candidates[$0].catalogId }))
		var isrcByCatalogId: [String: String] = [:]
		for start in stride(from: 0, to: uniqueIds.count, by: 50) {
			let chunk = Array(uniqueIds[start..<min(start + 50, uniqueIds.count)])
			do {
				let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
				for catalogSong in try await request.response().items {
					if let isrc = catalogSong.isrc { isrcByCatalogId[catalogSong.id.rawValue] = isrc }
				}
			} catch {
				print("[AppleMusicImport] catalog lookup failed for \(chunk.count) ids: \(error)")
			}
		}
		for index in needLookup {
			if let id = candidates[index].catalogId, let isrc = isrcByCatalogId[id] { candidates[index].isrc = isrc }
		}
		self.phase = .importing(step: .fetchingIsrc, progress: handled(), total: total)

		// 3. Apple Music catalog search.
		let searchIdx = candidates.indices.filter { candidates[$0].isrc == nil }
		let searchBase = handled()
		let searchSnapshot = candidates
		let searched = await Self.concurrentMap(searchIdx, width: 5, onProgress: { done in
			self.phase = .importing(step: .fetchingIsrc, progress: searchBase + Double(done), total: total)
		}) { (index: Int) -> String? in
			await Self.searchAppleCatalog(for: searchSnapshot[index])
		}
		for (index, isrc) in zip(searchIdx, searched) where isrc != nil { candidates[index].isrc = isrc }

		// 4. Deezer, only for what's still unknown. Deezer allows ~50 calls / 5 s and each track costs two,
		// so two at a time with a pause after each keeps well under it.
		let deezerIdx = candidates.indices.filter { candidates[$0].isrc == nil }
		if !deezerIdx.isEmpty {
			let deezerBase = handled()
			let deezerSnapshot = candidates
			self.phase = .importing(step: .searchingThirdParty, progress: deezerBase, total: total)
			let found = await Self.concurrentMap(deezerIdx, width: 2, onProgress: { done in
				self.phase = .importing(step: .searchingThirdParty, progress: deezerBase + Double(done), total: total)
			}) { (index: Int) -> String? in
				let isrc = await Self.deezerISRC(for: deezerSnapshot[index])
				try? await Task.sleep(for: .milliseconds(300))
				return isrc
			}
			for (index, isrc) in zip(deezerIdx, found) where isrc != nil { candidates[index].isrc = isrc }
		}

		// Tracks without an ISRC are still requested: `getByIsrc` falls back to title + artist. Only a track
		// with no title has nothing to search with.
		var seen: Set<String> = []
		var entries: [ISRCEntry] = []
		for candidate in candidates {
			guard !candidate.title.isEmpty else {
				missing.append(MissingTrack(title: candidate.title, artist: candidate.artist))
				continue
			}
			let key = candidate.isrc ?? "\(Self.normalized(Self.coreTitle(candidate.title)))|\(Self.normalized(candidate.artist))"
			if seen.insert(key).inserted {
				entries.append(ISRCEntry(isrc: candidate.isrc, title: candidate.title, artist: candidate.artist))
			}
		}
		return (entries, missing)
	}

	// MARK: - Apple Music API

	private struct LibraryTracksPage: Decodable {
		struct Item: Decodable {
			struct Attributes: Decodable {
				struct PlayParams: Decodable { let catalogId: String? }
				let name: String?
				let artistName: String?
				let durationInMillis: Int?
				let playParams: PlayParams?
			}
			struct Relationships: Decodable {
				struct Catalog: Decodable {
					struct CatalogItem: Decodable {
						struct CatalogAttributes: Decodable { let isrc: String? }
						let id: String
						let attributes: CatalogAttributes?
					}
					let data: [CatalogItem]?
				}
				let catalog: Catalog?
			}
			let attributes: Attributes?
			let relationships: Relationships?
		}
		let data: [Item]
		let next: String?
	}

	/// Every track of a library playlist with its catalog counterpart's ISRC (when the track has one),
	/// following the API's paging. Uploaded/local files have no catalog counterpart, so no ISRC here.
	private static func libraryCandidates(of playlistId: MusicItemID) async throws -> [Candidate] {
		var result: [Candidate] = []
		var offset = 0

		while true {
			guard var components = URLComponents(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistId.rawValue)/tracks") else { break }
			components.queryItems = [
				URLQueryItem(name: "include", value: "catalog"),
				URLQueryItem(name: "limit", value: "100"),
				URLQueryItem(name: "offset", value: String(offset)),
			]
			guard let url = components.url else { break }

			let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
			let page = try JSONDecoder().decode(LibraryTracksPage.self, from: response.data)

			for item in page.data {
				let catalog = item.relationships?.catalog?.data?.first
				result.append(Candidate(
					title: item.attributes?.name ?? "",
					artist: item.attributes?.artistName ?? "",
					duration: item.attributes?.durationInMillis.map { Double($0) / 1000 },
					isrc: catalog?.attributes?.isrc,
					catalogId: catalog?.id ?? item.attributes?.playParams?.catalogId
				))
			}

			guard page.next != nil, !page.data.isEmpty else { break }
			offset += page.data.count
		}
		return result
	}

	// MARK: - MusicKit lookups

	/// Every track of `playlist`, following `nextBatch()` — `with(.tracks)` only loads the first page.
	private static func allTracks(of playlist: MusicKit.Playlist) async throws -> [MusicKit.Track] {
		let detailed = try await playlist.with(.tracks)
		guard var collection = detailed.tracks else { return [] }

		var result = Array(collection)
		while collection.hasNextBatch, let next = try await collection.nextBatch() {
			result.append(contentsOf: next)
			collection = next
		}
		return result
	}

	/// The catalog ID behind a library song, read from its play parameters (its own `id` is a library ID).
	private static func catalogID(of song: Song) -> String? {
		guard let parameters = song.playParameters,
			  let data = try? JSONEncoder().encode(parameters),
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		if let catalogId = json["catalogId"] as? String { return catalogId }
		if (json["isLibrary"] as? Bool) != true, let id = json["id"] as? String { return id }
		return nil
	}

	private static func searchAppleCatalog(for candidate: Candidate) async -> String? {
		guard !candidate.title.isEmpty else { return nil }

		var request = MusicCatalogSearchRequest(term: "\(Self.coreTitle(candidate.title, keepDisplay: true)) \(candidate.artist)", types: [Song.self])
		request.limit = 10
		do {
			let songs = try await request.response().songs
			let hits = songs.compactMap { song in
				song.isrc.map { Hit(id: song.id.rawValue, title: song.title, artist: song.artistName, duration: song.duration, isrc: $0) }
			}
			return Self.bestMatch(for: candidate, in: hits)?.isrc
		} catch {
			print("[AppleMusicImport] catalog search failed for \(candidate.title): \(error)")
			return nil
		}
	}

	// MARK: - Deezer (last resort)

	private struct DeezerSearch: Decodable {
		struct Track: Decodable {
			struct Artist: Decodable { let name: String }
			let id: Int
			let title: String
			let duration: Int?
			let artist: Artist
		}
		let data: [Track]
	}

	private struct DeezerTrack: Decodable { let isrc: String? }

	private static func deezerISRC(for candidate: Candidate) async -> String? {
		guard !candidate.title.isEmpty else { return nil }

		let title = Self.coreTitle(candidate.title, keepDisplay: true).replacingOccurrences(of: "\"", with: "")
		let artist = candidate.artist.replacingOccurrences(of: "\"", with: "")

		// Structured query first, plain text if it finds nothing.
		for query in ["artist:\"\(artist)\" track:\"\(title)\"", "\(title) \(artist)"] {
			var components = URLComponents(string: "https://api.deezer.com/search/track")
			components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "10")]
			guard let url = components?.url,
				  let (data, _) = try? await URLSession.shared.data(from: url),
				  let search = try? JSONDecoder().decode(DeezerSearch.self, from: data)
			else { continue }

			let hits = search.data.map { Hit(id: String($0.id), title: $0.title, artist: $0.artist.name, duration: $0.duration.map(Double.init), isrc: nil) }
			guard let hit = Self.bestMatch(for: candidate, in: hits),
				  let trackURL = URL(string: "https://api.deezer.com/track/\(hit.id)"),
				  let (trackData, _) = try? await URLSession.shared.data(from: trackURL),
				  let isrc = (try? JSONDecoder().decode(DeezerTrack.self, from: trackData))?.isrc, !isrc.isEmpty
			else { continue }

			return isrc
		}
		return nil
	}

	// MARK: - Matching

	private struct Hit {
		let id: String
		let title: String
		let artist: String
		let duration: TimeInterval?
		let isrc: String?
	}

	private static func normalized(_ text: String) -> String {
		text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
			.filter { $0.isLetter || $0.isNumber }
	}

	/// The title without decoration that differs between libraries and catalogs: "(feat. X)", "[Remastered]",
	/// " - Remastered 2011", " feat. X". `keepDisplay` returns readable text for a query instead of a
	/// comparison key.
	private static func coreTitle(_ title: String, keepDisplay: Bool = false) -> String {
		var core = title.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
		if let range = core.range(of: " - ") { core = String(core[..<range.lowerBound]) }
		for marker in [" feat.", " feat ", " ft.", " ft ", " featuring "] {
			if let range = core.range(of: marker, options: .caseInsensitive) { core = String(core[..<range.lowerBound]) }
		}
		core = core.trimmingCharacters(in: .whitespaces)
		if core.isEmpty { core = title }
		return keepDisplay ? core : Self.normalized(core)
	}

	private static func artistsMatch(_ a: String, _ b: String) -> Bool {
		let (x, y) = (Self.normalized(a), Self.normalized(b))
		if x.isEmpty || y.isEmpty { return true }
		return x.contains(y) || y.contains(x)
	}

	/// Best hit for `candidate`: same core title, then preferring matching artist + close duration, then
	/// matching artist, then a very close duration alone (artist credits differ a lot across catalogs).
	private static func bestMatch(for candidate: Candidate, in hits: [Hit]) -> Hit? {
		let title = Self.coreTitle(candidate.title)
		let sameTitle = hits.filter { Self.coreTitle($0.title) == title }

		func close(_ hit: Hit, within seconds: Double) -> Bool {
			guard let a = hit.duration, let b = candidate.duration else { return true }
			return abs(a - b) <= seconds
		}

		return sameTitle.first { Self.artistsMatch($0.artist, candidate.artist) && close($0, within: 5) }
			?? sameTitle.first { Self.artistsMatch($0.artist, candidate.artist) }
			?? sameTitle.first { $0.duration != nil && candidate.duration != nil && close($0, within: 2) }
	}

	/// `transform` over `items`, `width` at a time, results in input order. `onProgress` gets the running
	/// count of finished items (on the main actor).
	private static func concurrentMap<Input: Sendable, Output: Sendable>(
		_ items: [Input],
		width: Int,
		onProgress: @MainActor @escaping (Int) -> Void,
		_ transform: @escaping @Sendable (Input) async -> Output
	) async -> [Output] {
		var results = [Output?](repeating: nil, count: items.count)
		var done = 0

		await withTaskGroup(of: (Int, Output).self) { group in
			var next = 0
			func enqueue() {
				guard next < items.count else { return }
				let index = next, item = items[next]
				next += 1
				group.addTask { (index, await transform(item)) }
			}

			for _ in 0..<min(width, items.count) { enqueue() }
			while let (index, output) = await group.next() {
				results[index] = output
				done += 1
				await onProgress(done)
				enqueue()
			}
		}
		return results.compactMap { $0 }
	}
}
