// Made by Lumaa

import AppIntents

/// Phrases people can say to Siri without any setup ("Put Dopamine Chamber on Nafyn"), on every device:
/// they are what classic Siri understands where Apple Intelligence isn't available. Siri with Apple
/// Intelligence goes through the `.audio` schema intents instead (`AudioIntents.swift`) and understands
/// free-form requests.
///
/// Every phrase is its own key in `AppShortcuts.xcstrings`, with one translation per language: to add a
/// language, translate each phrase (keep `${…}` and `${applicationName}` as they are) and each short title
/// there. A phrase added here needs its translations added there too. The system allows ten shortcuts at
/// most, and every phrase must contain `\(.applicationName)`.
struct NafynShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		// anything by name: song, album, artist or playlist
		AppShortcut(
			intent: PlayLibraryItemIntent(),
			phrases: [
				"Play \(\.$item) on \(.applicationName)",
				"Put \(\.$item) on \(.applicationName)",
				"Put on \(\.$item) on \(.applicationName)",
				"Listen to \(\.$item) on \(.applicationName)",
				"Start \(\.$item) on \(.applicationName)",
				"Play \(\.$item) with \(.applicationName)",
				"Play \(\.$item) in \(.applicationName)",
				"Put \(\.$item) in \(.applicationName)",
				"Open \(.applicationName) and play \(\.$item)",
				"\(.applicationName), play \(\.$item)",
			],
			shortTitle: "Play",
			systemImageName: "play.fill"
		)

		AppShortcut(
			intent: PlaySongIntent(),
			phrases: [
				"Play the song \(\.$song) on \(.applicationName)",
				"Put the song \(\.$song) on \(.applicationName)",
				"Play the track \(\.$song) on \(.applicationName)",
			],
			shortTitle: "intent-play-song",
			systemImageName: "music.note"
		)

		AppShortcut(
			intent: PlayAlbumIntent(),
			phrases: [
				"Play the album \(\.$album) on \(.applicationName)",
				"Put the album \(\.$album) on \(.applicationName)",
				"Listen to the album \(\.$album) on \(.applicationName)",
			],
			shortTitle: "intent-play-album",
			systemImageName: "square.stack"
		)

		AppShortcut(
			intent: PlayPlaylistIntent(),
			phrases: [
				"Play my \(\.$playlist) playlist on \(.applicationName)",
				"Play the playlist \(\.$playlist) on \(.applicationName)",
				"Put on my \(\.$playlist) playlist on \(.applicationName)",
			],
			shortTitle: "intent-play-playlist",
			systemImageName: "music.note.list"
		)

		AppShortcut(
			intent: ShuffleLibraryIntent(),
			phrases: [
				"Shuffle my music on \(.applicationName)",
				"Shuffle my library on \(.applicationName)",
				"Play some music on \(.applicationName)",
				"Put some music on \(.applicationName)",
			],
			shortTitle: "intent-shuffle-library",
			systemImageName: "shuffle"
		)

		AppShortcut(
			intent: ControlPlaybackIntent(action: .pause),
			phrases: [
				"Pause \(.applicationName)",
				"Pause the music on \(.applicationName)",
				"Stop the music on \(.applicationName)",
			],
			shortTitle: "Pause",
			systemImageName: "pause.fill"
		)

		AppShortcut(
			intent: ControlPlaybackIntent(action: .play),
			phrases: [
				"Resume \(.applicationName)",
				"Resume the music on \(.applicationName)",
				"Keep playing on \(.applicationName)",
			],
			shortTitle: "Resume",
			systemImageName: "play.fill"
		)

		AppShortcut(
			intent: ControlPlaybackIntent(action: .next),
			phrases: [
				"Next track on \(.applicationName)",
				"Skip on \(.applicationName)",
				"Skip this song on \(.applicationName)",
			],
			shortTitle: "intent-action-next-track",
			systemImageName: "forward.fill"
		)

		AppShortcut(
			intent: ControlPlaybackIntent(action: .previous),
			phrases: [
				"Previous track on \(.applicationName)",
				"Go back on \(.applicationName)",
				"Play the previous song on \(.applicationName)",
			],
			shortTitle: "intent-action-previous-track",
			systemImageName: "backward.fill"
		)
	}
}
