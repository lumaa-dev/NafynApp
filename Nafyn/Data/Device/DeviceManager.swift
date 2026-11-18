// Made by Lumaa

import Foundation

/// Identifies the device Nafyn runs on (model, OS, marketing name, symbol), meant for analytics.
///
/// Never branch a layout on it: screens adapt to their window, not to the device (CLAUDE.md, "Adapt to the
/// window, never the device"). Everything is read from the model identifier, never `userInterfaceIdiom`, so
/// an iPad app running on a Mac or an Apple Vision Pro ("Designed for iPad") reports that real device.
final class DeviceManager {
	static let shared: DeviceManager = .init()

	/// The hardware model identifier, e.g. `iPhone19,4`. In the Simulator, the simulated device's.
	let modelIdentifier: String
	let destination: DeviceManager.Destination
	/// The marketing name from ``modelNames`` (e.g. "iPhone Duo"), or the generic device type when unknown.
	let modelName: String

	let hasDynamicIsland: Bool
	/// A foldable device (iPhone Duo).
	let isFoldable: Bool
	/// Every iPhone and iPad, and the MacBook Pro with a touch screen.
	let hasTouchScreen: Bool
	/// An iPad app running on a Mac or an Apple Vision Pro ("Designed for iPad").
	let isCompatibilityMode: Bool

	var isSimulator: Bool {
		#if targetEnvironment(simulator)
		return true
		#else
		return false
		#endif
	}

	/// The operating system used by the device
	let deviceOS: String
	/// The user-friendly type of the device (Mac, iPhone, Vision)
	let deviceType: String
	/// The user-friendly name of the device
	let deviceName: String
	/// The SF Symbol for the current device
	let deviceSymbol: String

	/// The running OS version, e.g. "27.1" (the macOS / visionOS version in compatibility mode)
	var osVersion: String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		return version.patchVersion == 0
			? "\(version.majorVersion).\(version.minorVersion)"
			: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	private init() {
		let identifier = Self.getModelIdentifier()
		let destination = Destination(modelIdentifier: identifier)

		self.modelIdentifier = identifier
		self.destination = destination
		self.modelName = Self.modelNames[identifier] ?? destination.localized
		self.hasDynamicIsland = Self.dynamicIslandModels.contains(identifier)
		self.isFoldable = Self.foldableModels.contains(identifier)
		self.hasTouchScreen = switch destination {
			case .iphone, .ipad: true
			case .mac: Self.touchScreenMacModels.contains(identifier)
			case .vision: false
		}
		self.isCompatibilityMode = destination == .mac || destination == .vision

		self.deviceOS = destination.os
		self.deviceType = destination.type
		#if targetEnvironment(simulator)
		self.deviceName = "\(self.modelName) Simulator"
		// the Simulator runs on a Mac: show the host's symbol
		self.deviceSymbol = MacModels(modelIdentifier: Self.sysctlString("hw.model") ?? "")?.systemImage ?? "macpro.gen2.fill"
		print("[DeviceManager] Target is a Simulator")
		#else
		self.deviceName = self.modelName
		self.deviceSymbol = Self.symbol(for: identifier, destination: destination)
		#endif

		print("[DeviceManager] Recognized \(self.modelName) (\(identifier)) \(self.hasDynamicIsland ? "with" : "without") Dynamic Island.")
	}

	// MARK: - Private Static

	/// iPhones with a Dynamic Island. The iPhone 16e and 17e keep the notch.
	private static let dynamicIslandModels: Set<String> = [
		"iPhone15,2", // iPhone 14 Pro
		"iPhone15,3", // iPhone 14 Pro Max
		"iPhone15,4", // iPhone 15
		"iPhone15,5", // iPhone 15 Plus
		"iPhone16,1", // iPhone 15 Pro
		"iPhone16,2", // iPhone 15 Pro Max
		"iPhone17,3", // iPhone 16
		"iPhone17,4", // iPhone 16 Plus
		"iPhone17,1", // iPhone 16 Pro
		"iPhone17,2", // iPhone 16 Pro Max
		"iPhone18,3", // iPhone 17
		"iPhone18,1", // iPhone 17 Pro
		"iPhone18,2", // iPhone 17 Pro Max
		"iPhone18,4", // iPhone Air
		"iPhone19,2", // iPhone 18 Pro
		"iPhone19,3", // iPhone 18 Pro Max (US)
		"iPhone19,7", // iPhone 18 Pro Max (Global)
		"iPhone19,4", // iPhone Duo (outer display)
	]

	private static let foldableModels: Set<String> = [
		"iPhone19,4", // iPhone Duo
	]

	private static let touchScreenMacModels: Set<String> = [
		"Mac17,10", // MacBook Pro (16-inch PROLED XDR, M5 Max)
		"Mac17,11", // MacBook Pro (14-inch PROLED XDR, M5 Max)
		"Mac17,12", // MacBook Pro (16-inch PROLED XDR, M5 Pro)
		"Mac17,13", // MacBook Pro (14-inch PROLED XDR, M5 Pro)
	]

	/// iPhones and iPads with a Home button.
	private static let homeButtonModels: Set<String> = [
		"iPhone12,8", // iPhone SE (2nd generation)
		"iPhone14,6", // iPhone SE (3rd generation)
		"iPad11,1", "iPad11,2", // iPad mini (5th generation)
		"iPad11,3", "iPad11,4", // iPad Air (3rd generation)
		"iPad11,6", "iPad11,7", // iPad (8th generation)
		"iPad12,1", "iPad12,2", // iPad (9th generation)
	]

	private static func symbol(for identifier: String, destination: Destination) -> String {
		switch destination {
			case .iphone:
				if Self.foldableModels.contains(identifier) {
					return "iphone.duo"
				} else if Self.homeButtonModels.contains(identifier) {
					return "iphone.gen1"
				}
				return Self.dynamicIslandModels.contains(identifier) ? "iphone.gen3" : "iphone.gen2"
			case .ipad:
				return Self.homeButtonModels.contains(identifier) ? "ipad.gen1" : "ipad.gen2"
			case .mac:
				return MacModels(modelIdentifier: identifier)?.systemImage ?? "macpro.gen2.fill" // MP Gen2 for Unknown Mac
			case .vision:
				return "vision.pro"
		}
	}

	private static func getModelIdentifier() -> String {
		if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
			return simulatorModel
		}

		// an iPad app on a Mac: `uname` only reports the architecture there, `hw.model` has the Mac's model
		if ProcessInfo.processInfo.isiOSAppOnMac, let macModel = Self.sysctlString("hw.model") {
			return macModel
		}

		var sysinfo = utsname()
		uname(&sysinfo)
		return withUnsafeBytes(of: &sysinfo.machine) { buffer in
			String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
		}
	}

	private static func sysctlString(_ name: String) -> String? {
		var size: Int = 0
		guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

		var value = [CChar](repeating: 0, count: size)
		guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
		return String(cString: value)
	}

	// MARK: - Enums

	enum Destination: CaseIterable {
		case mac
		case iphone
		case ipad
		case vision

		init(modelIdentifier: String) {
			if modelIdentifier.hasPrefix("iPhone") {
				self = .iphone
			} else if modelIdentifier.hasPrefix("iPad") {
				self = .ipad
			} else if modelIdentifier.hasPrefix("RealityDevice") {
				self = .vision
			} else if modelIdentifier.hasPrefix("Mac") || modelIdentifier.hasPrefix("iMac") || ProcessInfo.processInfo.isiOSAppOnMac {
				self = .mac
			} else {
				self = .iphone
			}
		}

		var localized: String {
			switch self {
				case .mac:
					"Mac"
				case .iphone:
					"iPhone"
				case .ipad:
					"iPad"
				case .vision:
					"Apple Vision"
			}
		}

		var type: String {
			switch self {
				case .mac:
					"Mac"
				case .iphone:
					"iPhone"
				case .ipad:
					"iPad"
				case .vision:
					"Vision"
			}
		}

		var os: String {
			switch self {
				case .mac:
					"macOS"
				case .iphone:
					"iOS"
				case .ipad:
					"iPadOS"
				case .vision:
					"visionOS"
			}
		}
	}

	enum MacModels: String {
		case macBookPro = "MacBook Pro"
		case macBookAir = "MacBook Air"
		case macBookNeo = "MacBook Neo"
		case macMini = "Mac mini"
		case macStudio = "Mac Studio"
		case iMac = "iMac"
		case macPro = "Mac Pro"

		/// Matched on the marketing name, so every Mac in ``DeviceManager/modelNames`` is covered without its
		/// own list of identifiers.
		init?(modelIdentifier: String) {
			guard let name = DeviceManager.modelNames[modelIdentifier] else { return nil }

			// "MacBook Pro" before any shorter prefix
			let families: [MacModels] = [.macBookPro, .macBookAir, .macBookNeo, .macMini, .macStudio, .iMac, .macPro]
			guard let family = families.first(where: { name.hasPrefix($0.rawValue) }) else { return nil }
			self = family
		}

		var systemImage: String {
			switch self {
				case .macBookPro, .macBookAir, .macBookNeo:
					"macbook"
				case .macMini:
					"macmini.fill"
				case .macStudio:
					"macstudio.fill"
				case .iMac:
					"desktopcomputer"
				case .macPro:
					"macpro.gen3.fill"
			}
		}
	}
}
