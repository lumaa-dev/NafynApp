// Made by Lumaa

import SwiftUI
import Safyn

/// Nafyn Unity controls: the account-wide on/off toggle, and — when another device is currently
/// master — a compact remote transport for it straight from Settings.
struct UnitySettingsSection: View {
	@State private var isUpdating = false

	private var remoteTrack: MediaRow? {
		guard let state = UnityEngine.shared.remoteState, state.queue.indices.contains(state.currentIndex) else { return nil }
		return try? state.queue[state.currentIndex].decode(MediaRow.self)
	}

	private var enabledBinding: Binding<Bool> {
		Binding(
			get: { UnityEngine.shared.isSettingEnabled },
			set: { newValue in
				self.isUpdating = true
				Task {
					await UnityEngine.shared.setEnabled(newValue)
					self.isUpdating = false
				}
			}
		)
	}

	var body: some View {
		Section {
			Toggle(String(localized: "unity-enabled"), isOn: self.enabledBinding)
				.disabled(self.isUpdating || NetworkMonitor.shared.isOffline)

			if UnityEngine.shared.isSettingEnabled {
				self.statusRow
			}
		}
		header: {
			Text(String(localized: "unity"))
		} footer: {
			Text(String(localized: "unity-footer"))
		}
	}

	@ViewBuilder
	private var statusRow: some View {
		if UnityEngine.shared.isMaster {
			Label(String(localized: "unity-playing-here"), systemImage: "hifispeaker.fill")
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
		} else if let track = self.remoteTrack {
			VStack(alignment: .leading, spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					if let device = UnityEngine.shared.masterDeviceLabel {
						Text(String(format: String(localized: "unity-playing-on"), device))
							.font(DTFont.system(12))
							.foregroundStyle(DTColor.textPrimary.opacity(0.55))
					}
					Text("\(track.title) • \(track.artistName)")
						.foregroundStyle(DTColor.textPrimary)
						.lineLimit(1)
				}

				HStack(spacing: 24) {
					Button {
						UnityEngine.shared.sendCommand(.prev)
					} label: {
						Image(systemName: "backward.fill")
					}
					.disabled(NetworkMonitor.shared.isOffline)

					Button {
						UnityEngine.shared.sendCommand(.togglePlay)
					} label: {
						Image(systemName: (UnityEngine.shared.remoteState?.isPlaying ?? false) ? "pause.fill" : "play.fill")
					}
					.disabled(NetworkMonitor.shared.isOffline)

					Button {
						UnityEngine.shared.sendCommand(.next)
					} label: {
						Image(systemName: "forward.fill")
					}
					.disabled(NetworkMonitor.shared.isOffline)

					Spacer()

					Button(String(localized: "unity-play-here")) {
						UnityEngine.shared.takeOverLocally()
					}
					.buttonStyle(.borderless)
				}
				.foregroundStyle(Color.primary)
				.tint(Color.primary)
			}
			.buttonStyle(.plain)
		} else {
			Label(String(localized: "unity-nobody-playing"), systemImage: "hifispeaker.slash")
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
		}
	}
}
