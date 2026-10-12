// Made by Lumaa

import Foundation
import Network

/// Global singleton reachability monitor, backing every "disable this control while offline" check
/// across the app (see call sites of `isOffline`).
///
/// `NWPath.status` is `.satisfied` for any usable interface, including a weak/expensive one (slow
/// cellular, one bar of Wi-Fi) — it only reports `.unsatisfied` when there's truly no route to the
/// internet at all (airplane mode, no SIM, Wi-Fi off with no cellular). That's exactly the "offline
/// entirely vs. just a weak signal" distinction this app wants: weak connections stay enabled and are
/// left to fail (or not) on their own merits, same as before this existed.
@Observable
final class NetworkMonitor {
	static let shared = NetworkMonitor()

	private(set) var isOffline = false

	private let monitor = NWPathMonitor()

	private init() {
		self.monitor.pathUpdateHandler = { [weak self] path in
			Task { @MainActor in
				self?.isOffline = (path.status == .unsatisfied)
			}
		}
		self.monitor.start(queue: DispatchQueue(label: "fr.lumaa.Nafyn.networkMonitor"))
	}
}
