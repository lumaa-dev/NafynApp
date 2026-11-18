// Made by Lumaa

import Foundation
import Safyn

extension MixLabel {
	/// The mix's title in the app's language (the server's `title` is English only).
	var localizedTitle: String {
		let main = self.kind == .artist
			? String(localized: "mix-title-artist-\(self.value)")
			: String(localized: "mix-title-\(Self.part(self.kind, self.value))")
		guard let qualifier = self.qualifier else { return main }
		return String(localized: "mix-title-qualified-\(main)-\(Self.part(qualifier.kind, qualifier.value))")
	}

	private static func part(_ kind: MixLabelKind, _ value: String) -> String {
		switch kind {
			case .genre:
				return value.capitalized
			case .mood:
				switch value {
					case "upbeat": return String(localized: "mix-mood-upbeat")
					case "intense": return String(localized: "mix-mood-intense")
					case "mellow": return String(localized: "mix-mood-mellow")
					case "melancholic": return String(localized: "mix-mood-melancholic")
					default: return value.capitalized
				}
			case .time:
				switch value {
					case "night": return String(localized: "mix-time-night")
					case "morning": return String(localized: "mix-time-morning")
					case "afternoon": return String(localized: "mix-time-afternoon")
					case "evening": return String(localized: "mix-time-evening")
					default: return value.capitalized
				}
			case .decade, .artist, .unknown:
				return value
		}
	}
}

extension RecommendationExplanation {
	/// Why the card is shown, `nil` when there is nothing to say.
	var text: String? {
		switch self.kind {
			case .becauseArtist:
				return self.subject.map { String(localized: "rec-why-because-artist-\($0)") }
			case .fromMix:
				return self.subject.map { String(localized: "rec-why-from-mix-\($0)") }
			case .newRelease:
				return String(localized: "rec-why-new-release")
			case .rediscover:
				return String(localized: "rec-why-rediscover")
			case .recentlyPlayed:
				return String(localized: "rec-why-recently-played")
			case .similarToRecent:
				return String(localized: "rec-why-similar-to-recent")
			case .none, .unknown:
				return nil
		}
	}
}

extension RecommendationShelfKind {
	var title: String {
		switch self {
			case .mixes: String(localized: "discover-shelf-mixes")
			case .suggestions: String(localized: "discover-shelf-suggestions")
			case .jumpBackIn: String(localized: "discover-shelf-jump-back-in")
			case .rediscover: String(localized: "discover-shelf-rediscover")
			case .playlists: String(localized: "discover-shelf-playlists")
			case .unknown: String(localized: "discover")
		}
	}
}

extension MixTrackReason {
	/// Why the track is in the mix.
	var text: String {
		if self.isFamiliar {
			if let plays = self.plays, plays > 0 { return String(localized: "mix-reason-familiar-plays-\(plays)") }
			return String(localized: "mix-reason-familiar")
		}
		if let artist = self.seedArtist { return String(localized: "mix-reason-novel-artist-\(artist)") }
		switch self.via {
			case "audio": return String(localized: "mix-reason-novel-audio")
			case "text": return String(localized: "mix-reason-novel-text")
			case "graph": return String(localized: "mix-reason-novel-graph")
			default: return String(localized: "mix-reason-novel-collaborative")
		}
	}
}
