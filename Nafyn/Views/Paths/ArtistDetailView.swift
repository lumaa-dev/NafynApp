// Made by Lumaa

import SwiftUI
import Safyn

struct ArtistDetailView: View {
	@Environment(\.server) private var server: NafynServer?

	var artistId: String

	private let colItems: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Artist.get(aid: self.artistId)) as ArtistDetail
		} content: { artist, _ in
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					VStack(spacing: 10) {
						CoverImage(url: artist.image.flatMap { URL(string: $0) })
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

					if !artist.albums.isEmpty {
						Text("discography")
							.font(DTFont.serifItalic(25))
							.foregroundStyle(DTColor.textPrimary)

						LazyVGrid(columns: self.colItems, spacing: 16) {
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

					if let url = URL(string: "https://musicbrainz.org/artist/\(artist.id)") {
						Link(String(localized: "view-on-musicbrainz"), destination: url)
							.font(DTFont.system(16))
							.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					}
				}
				.padding()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
		}
		.navigationBarTitleDisplayMode(.inline)
	}
}
