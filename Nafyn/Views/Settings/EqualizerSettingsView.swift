// Made by Lumaa

import SwiftUI

/// Settings ▸ Equalizer: the on/off switch, ten vertical band sliders drawn over the frequency curve and the
/// live spectrum, and the presets. Everything saves the moment it changes and is local to this device.
struct EqualizerSettingsView: View {
	private let engine = EqualizerEngine.shared

	/// Gap between the panel's edge and the first and last band column.
	private static let panelInset: CGFloat = 10

	var body: some View {
		// One view carries the toolbar: on a `Group` the modifier is applied to every child, one Reset button per section
		SettingsSectionScreen(title: String(localized: "equalizer")) {
			Section {
				Toggle(String(localized: "eq-enabled"), isOn: Binding(
					get: { self.engine.isEnabled },
					set: { self.engine.isEnabled = $0 }
				))
			}

			Section {
				self.panel
					.listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
					.listRowBackground(Color.clear)
			} footer: {
				if PlaybackSource.isEqualizerApplicable {
					Text(String(localized: "eq-footer"))
				} else {
					Text(String(localized: "eq-remote-footer"))
				}
			}

			Section {
				ForEach(EqualizerEngine.presets) { preset in
					Button {
						self.engine.apply(preset)
					} label: {
						HStack {
							Text(preset.name)
							Spacer()
							if self.engine.activePreset?.id == preset.id {
								Image(systemName: "checkmark")
							}
						}
						.contentShape(Rectangle())
					}
					.foregroundStyle(Color.primary)
					.tint(Color.primary)
				}

				if self.engine.activePreset == nil {
					HStack {
						Text(String(localized: "eq-preset-custom"))
						Spacer()
						Image(systemName: "checkmark")
					}
					.foregroundStyle(Color.primary)
				}
			} header: {
				Text(String(localized: "eq-presets"))
			}
		}
		.listStyle(.insetGrouped)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					self.engine.reset()
				} label: {
					Label(String(localized: "reset"), systemImage: "arrow.counterclockwise")
				}
				.tint(Color.primary)
				.disabled(self.engine.isFlat)
			}
		}
	}

	/// The visualizer with a slider column for each band laid over it, and the frequency labels below. The
	/// sliders and the canvas share one width, one column per band, so every thumb sits on the curve.
	private var panel: some View {
		VStack(spacing: 10) {
			ZStack {
				RoundedRectangle(cornerRadius: 26, style: .continuous)
					.fill(Color(hex: "0B0B12"))

				EQVisualizer(
					gains: self.engine.gains,
					isLive: PlaybackSource.isSpectrumLive
				)
				.padding(.horizontal, Self.panelInset)

				HStack(spacing: 0) {
					ForEach(Array(EQScale.bandFrequencies.enumerated()), id: \.offset) { index, frequency in
						EQBandSlider(frequency: frequency, gain: self.engine.gains[index]) { value in
							self.engine.setGain(value, at: index)
						}
						.frame(maxWidth: .infinity)
					}
				}
				.padding(.horizontal, Self.panelInset)
			}
			.frame(height: 280)
			.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

			HStack(spacing: 0) {
				ForEach(Array(EQScale.bandFrequencies.enumerated()), id: \.offset) { _, frequency in
					Text(EQBandSlider.label(for: frequency))
						.font(DTFont.system(11, weight: .medium))
						.monospacedDigit()
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
				}
			}
			.padding(.horizontal, Self.panelInset)
			.accessibilityHidden(true)
		}
		.opacity(self.engine.isEnabled ? 1 : 0.45)
		.animation(.easeOut(duration: 0.2), value: self.engine.isEnabled)
		.allowsHitTesting(self.engine.isEnabled)
	}
}
