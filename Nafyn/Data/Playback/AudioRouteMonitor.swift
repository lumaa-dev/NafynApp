// Made by Lumaa

import AVFAudio
import SwiftUI

/// Follows the audio session's current output (AirPlay, Bluetooth, car, wired) and exposes its simplified
/// name and SF Symbol, shown on Now Playing's AirPlay pill. The device's own speaker reads as "AirPlay".
@MainActor
@Observable
final class AudioRouteMonitor {
	static let shared = AudioRouteMonitor()

	/// The connected output's simplified name, `nil` when playing on this device.
	private(set) var deviceName: String? = nil
	private(set) var deviceSymbol: Image = Image(systemName: "airplay.audio")

	private init() {
		self.refresh()

		// the notification is posted off the main thread; this task inherits the main actor, so updates land there
		Task { [weak self] in
			for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
				self?.refresh()
			}
		}
	}

	private func refresh() {
		guard
			let output = AVAudioSession.sharedInstance().currentRoute.outputs.first,
			output.portType != .builtInSpeaker,
			output.portType != .builtInReceiver
		else {
			self.deviceName = nil
			self.deviceSymbol = Image(systemName: "airplay.audio")
			return
		}

		let device = DeviceType.matchName(output.portName, port: output.portType)
		self.deviceName = device.name
		self.deviceSymbol = device.image
	}
}
