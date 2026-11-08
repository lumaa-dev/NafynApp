// Made by Lumaa

import SwiftUI
import Safyn

struct ArtistDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var artistId: String


	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Artist.get(aid: self.artistId)) as ArtistDetail
		} content: { artist, _ in
			// Regular width (Duo inner display, iPad): portrait and bio in one pane, the discography in the other.
			AdaptiveDetail {
				VStack(alignment: .leading, spacing: 16) {
					self.about(artist)
					self.discography(artist)
					self.musicBrainzLink(artist)
				}
			} primary: {
				VStack(alignment: .leading, spacing: 16) {
					self.about(artist)
					self.musicBrainzLink(artist)
				}
			} secondary: {
				self.discography(artist)
			}
		}
		.navigationBarTitleDisplayMode(.inline)
	}

	/// Portrait, name, listener count and bio.
	@ViewBuilder
	private func about(_ artist: ArtistDetail) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(spacing: 10) {
				ArtistPhoto(artistId: artist.id, fallback: artist.image.flatMap { URL(string: $0) })
					.clipShape(Circle())
					.frame(width: 140, height: 140)

				Text(artist.name)
					.font(DTFont.serif(31))
					.foregroundStyle(DTColor.textPrimary)
					.multilineTextAlignment(.center)

				if let listeners = artist.listeners {
					Text(String(localized: "listeners \(Int(listeners))"))
						.font(DTFont.system(16))
						.foregroundStyle(DTColor.textPrimary.opacity(0.5))
				}
			}
			.frame(maxWidth: .infinity)

			if let bio = artist.bio, !bio.isEmpty {
				Text(bio)
					.font(DTFont.system(18))
					.foregroundStyle(DTColor.textPrimary.opacity(0.8))
			}
		}
	}

	/// The discography by kind (DESIGN.md "Artist"): a category grid each - Albums, EPs, Singles... - one row of
	/// cards that scrolls sideways, newest first. From a server older than the categories, the plain grid.
	@ViewBuilder
	private func discography(_ artist: ArtistDetail) -> some View {
		if !artist.categories.isEmpty {
			VStack(alignment: .leading, spacing: 24) {
				ForEach(artist.categories) { category in
					ReleaseGrid(title: category.id.title) {
						ForEach(category.releases) { release in
							NavigationLink(value: release.destination) {
								MusicCard(.info(release.media))
									.frame(width: ReleaseGridLayout.cardWidth)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
		} else if !artist.albums.isEmpty {
			VStack(alignment: .leading, spacing: 16) {
				Text("discography")
					.font(DTFont.serifItalic(25))
					.foregroundStyle(DTColor.textPrimary)

				FoldGrid(spacing: 16) {
					ForEach(artist.albums, id: \.id) { album in
						if let destination = MusicCardEntry.info(album).destination {
							NavigationLink(value: destination) {
								MusicCard(.info(album))
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private func musicBrainzLink(_ artist: ArtistDetail) -> some View {
		if let url = URL(string: "https://musicbrainz.org/artist/\(artist.id)") {
			Link(String(localized: "view-on-musicbrainz"), destination: url)
				.font(DTFont.system(16))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))
		}
	}
}
