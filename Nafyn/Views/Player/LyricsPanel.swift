// Made by Lumaa

import SwiftUI
import Safyn

struct LyricsPanel: View {
	@Environment(\.server) private var server: NafynServer?

	var trackId: String

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			return try await server.send(Library.lyrics(id: self.trackId)) as Lyrics
		} content: { lyrics, _ in
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					ForEach(lyrics.paragraphs, id: \.id) { paragraph in
						ForEach(paragraph.lines, id: \.id) { line in
							Text(line.text)
								.font(DTFont.serif(22))
								.foregroundStyle(self.isActive(line) ? DTColor.textPrimary : DTColor.textPrimary.opacity(0.4))
						}
					}
				}
				.padding()
			}
			.scrollEdgeEffectStyle(.soft, for: .all)
		}
	}

	private func isActive(_ line: Lyrics.Line) -> Bool {
		let time = PlayerEngine.shared.currentTime
		return time >= line.startTime && time <= line.endTime
	}
}
