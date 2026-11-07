// Made by Lumaa

import Foundation
import ActivityKit
import Safyn

/// Wires the two server-started Live Activities to the server.
///
/// The server starts them through push-to-start, so this never starts one locally (that would duplicate
/// it). It only reports the push-to-start tokens, and — for every activity that appears, including ones a
/// push started while the app wasn't running — the per-activity update token the server needs to update
/// and end it. Ending needs no cleanup here: the server deletes the tokens itself.
final class LiveActivityCoordinator {
	static let shared = LiveActivityCoordinator()

	private var hasStarted = false
	private var observedActivities: Set<String> = []

	private init() {}

	func start() {
		guard !self.hasStarted else { return }
		self.hasStarted = true

		Task {
			if let token = Activity<NafynRequestActivityAttributes>.pushToStartToken {
				PushManager.shared.submit(token: token, kind: .laStartRequest)
			}
			for await token in Activity<NafynRequestActivityAttributes>.pushToStartTokenUpdates {
				PushManager.shared.submit(token: token, kind: .laStartRequest)
			}
		}

		Task {
			if let token = Activity<NafynReleaseCountdownAttributes>.pushToStartToken {
				PushManager.shared.submit(token: token, kind: .laStartRelease)
			}
			for await token in Activity<NafynReleaseCountdownAttributes>.pushToStartTokenUpdates {
				PushManager.shared.submit(token: token, kind: .laStartRelease)
			}
		}

		Task {
			for activity in Activity<NafynRequestActivityAttributes>.activities {
				self.observe(activity)
			}
			for await activity in Activity<NafynRequestActivityAttributes>.activityUpdates {
				// the server keeps one request activity per user; this is the on-device guard for a stray one
				// it could not end (its update token never reached the server)
				await self.endOtherRequestActivities(keeping: activity)
				self.observe(activity)
			}
		}

		Task {
			for activity in Activity<NafynReleaseCountdownAttributes>.activities {
				self.observe(activity)
			}
			for await activity in Activity<NafynReleaseCountdownAttributes>.activityUpdates {
				self.observe(activity)
			}
		}
	}

	/// Only one request Live Activity may sit on the Lock Screen: a new one replaces whatever is still there.
	private func endOtherRequestActivities(keeping activity: Activity<NafynRequestActivityAttributes>) async {
		for other in Activity<NafynRequestActivityAttributes>.activities where other.id != activity.id {
			await other.end(nil, dismissalPolicy: .immediate)
		}
	}

	private func observe(_ activity: Activity<NafynRequestActivityAttributes>) {
		guard self.observedActivities.insert(activity.id).inserted else { return }
		let requestId = activity.attributes.requestId
		Task {
			for await token in activity.pushTokenUpdates {
				PushManager.shared.registerActivity(kind: .request, refId: requestId, token: token)
			}
		}
	}

	private func observe(_ activity: Activity<NafynReleaseCountdownAttributes>) {
		guard self.observedActivities.insert(activity.id).inserted else { return }
		let subscriptionId = activity.attributes.subscriptionId
		Task {
			for await token in activity.pushTokenUpdates {
				PushManager.shared.registerActivity(kind: .release, refId: subscriptionId, token: token)
			}
		}
	}
}
