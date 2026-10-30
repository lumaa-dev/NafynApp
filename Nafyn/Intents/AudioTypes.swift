// Made by Lumaa

import AppIntents
import CoreSpotlight
import Foundation
import Safyn

// MARK: - Warm-up result

/// Handle to a queue prepared by ``WarmupAudioQueueIntent``: `PlayAudioIntent` starts it without loading it again.
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct WarmupAudioQueueResult: TransientAppEntity {
	/// Key of the prepared queue in ``AudioPlayback``.
	var queueId = UUID()

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "Prepared queue")
	}

	init() {}

	init(queueId: UUID) {
		self.queueId = queueId
	}
}

// MARK: - Enums

@AppEnum(schema: .audio.playbackAttributes)
enum PlaybackAttributes: String {
	case shuffle
	case `repeat`

	static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.shuffle: "Shuffle",
		.repeat: "Repeat",
	]
}

@AppEnum(schema: .audio.queueInsertionLocation)
enum QueueInsertionLocation: String {
	case next
	case tail

	static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.next: "Play Next",
		.tail: "Play Last",
	]
}

/// What Siri can ask to play.
@UnionValue
enum AudioItem {
	case song(SongEntity)
	case album(AlbumEntity)
	case artist(ArtistEntity)
	case playlist(PlaylistEntity)
}
