// Made by Lumaa

import AppIntents

/// Phrases people can say to Siri without any setup ("Play Dopamine Chamber on Nafyn"), on every device:
/// they are what classic Siri understands where Apple Intelligence isn't available. Siri with Apple
/// Intelligence goes through the `.audio` schema intents instead (`AudioIntents.swift`) and understands
/// free-form requests. Localized in `AppShortcuts.xcstrings`.
struct NafynShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: PlayAlbumIntent(),
			phrases: [
				"Play \(\.$album) on \(.applicationName)",
				"Play the album \(\.$album) on \(.applicationName)",
			],
			shortTitle: "Play Album",
			systemImageName: "square.stack"
		)

		AppShortcut(
			intent: PlaySongIntent(),
			phrases: [
				"Play \(\.$song) on \(.applicationName)",
				"Play the song \(\.$song) on \(.applicationName)",
			],
			shortTitle: "Play Song",
			systemImageName: "music.note"
		)

		AppShortcut(
			intent: PlayPlaylistIntent(),
			phrases: [
				"Play my \(\.$playlist) playlist on \(.applicationName)",
				"Play the playlist \(\.$playlist) on \(.applicationName)",
			],
			shortTitle: "Play Playlist",
			systemImageName: "music.note.list"
		)

		AppShortcut(
			intent: ShuffleLibraryIntent(),
			phrases: [
				"Shuffle my music on \(.applicationName)",
				"Shuffle my library on \(.applicationName)",
				"Play some music on \(.applicationName)",
			],
			shortTitle: "Shuffle My Library",
			systemImageName: "shuffle"
		)

		AppShortcut(
			intent: PauseNafynIntent(),
			phrases: ["Pause \(.applicationName)"],
			shortTitle: "Pause",
			systemImageName: "pause.fill"
		)

		AppShortcut(
			intent: ResumeNafynIntent(),
			phrases: ["Resume \(.applicationName)"],
			shortTitle: "Resume",
			systemImageName: "play.fill"
		)

		AppShortcut(
			intent: NextTrackIntent(),
			phrases: ["Next track on \(.applicationName)", "Skip on \(.applicationName)"],
			shortTitle: "Next Track",
			systemImageName: "forward.fill"
		)

		AppShortcut(
			intent: PreviousTrackIntent(),
			phrases: ["Previous track on \(.applicationName)"],
			shortTitle: "Previous Track",
			systemImageName: "backward.fill"
		)
	}
}
