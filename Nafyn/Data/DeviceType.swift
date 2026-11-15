// Made by Lumaa

import AVFAudio
import SwiftUI

/// Recognizes an audio output (AirPods, HomePod, Beats, car, wired headphones...) from its port name and
/// type, giving it a simplified name and its matching SF Symbol for the Now Playing AirPlay pill.
enum DeviceType {
	enum AirPods: TypedDevice {
		// normal
		case gen1
		case gen3
		case gen4

		// pro
		case pro
		case proGen3

		// headset
		case max

		var name: String {
			switch self {
				case .gen1:
					"AirPods"
				case .gen3:
					"AirPods 3"
				case .gen4:
					"AirPods 4"
				case .pro:
					"AirPods Pro"
				case .proGen3:
					"AirPods Pro 3"
				case .max:
					"AirPods Max"
			}
		}

		var image: Image {
			switch self {
				case .gen1:
					Image(systemName: "airpods")
				case .gen3:
					Image(systemName: "airpods.gen3")
				case .gen4:
					Image(systemName: "airpods.gen4")
				case .pro:
					Image(systemName: "airpods.pro")
				case .proGen3:
					Image(systemName: "airpods.pro.gen3")
				case .max:
					Image(systemName: "airpods.max")
			}
		}
	}

	enum HomePod: TypedDevice {
		case `default`
		case mini

		var name: String {
			switch self {
				case .default:
					"HomePod"
				case .mini:
					"HomePod Mini"
			}
		}

		var image: Image {
			switch self {
				case .default:
					Image(systemName: "homepod")
				case .mini:
					Image(systemName: "homepod.mini")
			}
		}
	}

	enum Beats: TypedDevice {
		// earphones
		case power
		case power3
		case powerPro
		case powerPro2
		case studiobuds
		case studiobudsPlus
		case solobuds

		// speaker
		case pill

		var name: String {
			switch self {
				case .power:
					"Powerbeats"
				case .power3:
					"Powerbeats 3"
				case .powerPro:
					"Powerbeats Pro"
				case .powerPro2:
					"Powerbeats Pro 2"
				case .studiobuds:
					"Studio Buds"
				case .studiobudsPlus:
					"Studio Buds +"
				case .solobuds:
					"Solo Buds"
				case .pill:
					"Beats Pill"
			}
		}

		var image: Image {
			switch self {
				case .power:
					Image(systemName: "beats.powerbeats")
				case .power3:
					Image(systemName: "beats.powerbeats3")
				case .powerPro:
					Image(systemName: "beats.powerbeats.pro")
				case .powerPro2:
					Image(systemName: "beats.powerbeats.pro.2")
				case .studiobuds:
					Image(systemName: "beats.studiobuds")
				case .studiobudsPlus:
					Image(systemName: "beats.studiobuds.plus")
				case .solobuds:
					Image(systemName: "beats.solobuds")
				case .pill:
					Image(systemName: "beats.pill")
			}
		}
	}

	enum Unknown: TypedDevice {
		/// Traditional earbuds
		case earbuds(String)
		/// In-ear earbuds (Beats Studio Buds)
		case inEarbuds(String)
		/// Traditional headphones
		case headphones(String)
		case car(String)
		/// Unknown type of device or whatever
		case other(String)

		var name: String {
			switch self {
				case .earbuds(let string), .inEarbuds(let string), .headphones(let string), .car(let string), .other(let string):
					return string
			}
		}

		var image: Image {
			switch self {
				case .earbuds:
					Image(systemName: "earbuds")
				case .inEarbuds:
					Image(systemName: "earbuds.bone.conduction")
				case .headphones:
					Image(systemName: "headphones")
				case .car:
					Image(systemName: "car")
				case .other:
					Image(systemName: "airplay.audio")
			}
		}
	}

	/// Matches a device from its port type first (car, wired headphones), then from its name.
	static func matchName(_ name: String, port: AVAudioSession.Port) -> any TypedDevice {
		switch port {
			case .carAudio:
				return DeviceType.Unknown.car(name)
			case .headphones:
				return DeviceType.Unknown.headphones(name)
			default:
				return Self.matchName(name)
		}
	}

	static func matchName(_ name: String) -> any TypedDevice {
		if let airpods = DeviceType.AirPods.matchName(name) {
			return airpods
		} else if let homepod = DeviceType.HomePod.matchName(name) {
			return homepod
		} else if let beats = DeviceType.Beats.matchName(name) {
			return beats
		} else {
			return DeviceType.Unknown.other(name)
		}
	}
}

// MARK: - Match types

extension DeviceType.AirPods {
	static func matchName(_ name: String) -> Self? {
		let formatted: String = name.lowercased()

		if formatted.contains("airpods") {
			if formatted.contains("airpods 3") {
				return Self.gen3
			} else if formatted.contains("airpods 4") {
				return Self.gen4
			} else if formatted.contains("airpods pro 3") {
				return Self.proGen3
			} else if formatted.contains("airpods pro") {
				return Self.pro
			} else if formatted.contains("airpods max") {
				return Self.max
			}

			return Self.gen1
		}

		return nil
	}
}

extension DeviceType.HomePod {
	static func matchName(_ name: String) -> Self? {
		let formatted: String = name.lowercased()

		if formatted.contains("homepod mini") {
			return Self.mini
		} else if formatted.contains("homepod") {
			return Self.default
		}

		return nil
	}
}

extension DeviceType.Beats {
	static func matchName(_ name: String) -> Self? {
		let formatted: String = name.lowercased()

		if formatted.contains("pill") {
			return Self.pill
		} else if formatted.contains("powerbeats 3") || formatted.contains("powerbeats3") {
			return Self.power3
		} else if formatted.contains("powerbeats pro 2") {
			return Self.powerPro2
		} else if formatted.contains("powerbeats pro") {
			return Self.powerPro
		} else if formatted.contains("powerbeats") {
			return Self.power
		} else if formatted.contains("solobuds") || formatted.contains("solo buds") {
			return Self.solobuds
		} else if formatted.contains("studio buds +") || formatted.contains("studio buds+") {
			return Self.studiobudsPlus
		} else if formatted.contains("studio buds") {
			return Self.studiobuds
		}

		return nil
	}
}

protocol TypedDevice {
	var name: String { get }
	var image: Image { get }
}
