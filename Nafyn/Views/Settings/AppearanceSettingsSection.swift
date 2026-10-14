// Made by Lumaa

import SwiftUI
import Safyn

struct AppearanceSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?
	@AppStorage(LyricsPanel.useSystemFontKey) private var lyricsUseSystemFont = false

	@State private var canManageFileSize = false
	@State private var showDuration = DisplayPreferences.shared.showDuration
	@State private var showFileSize = DisplayPreferences.shared.showFileSize

	private var themeBinding: Binding<AppTheme> {
		Binding(
			get: { ThemeManager.shared.current },
			set: { ThemeManager.shared.current = $0 }
		)
	}

	var body: some View {
		Section {
			Picker(String(localized: "theme"), selection: self.themeBinding) {
				ForEach(AppTheme.allCases) { theme in
					Label(theme.label, systemImage: theme.symbolName)
						.tag(theme)
				}
			}

			Toggle(String(localized: "lyrics-system-font"), isOn: self.$lyricsUseSystemFont)

			Toggle(String(localized: "show-duration"), isOn: self.$showDuration)
				.onChange(of: self.showDuration) { _, newValue in
					DisplayPreferences.shared.showDuration = newValue
					self.pushUpdate(showDuration: newValue)
				}

			if self.canManageFileSize {
				Toggle(String(localized: "show-file-size"), isOn: self.$showFileSize)
					.onChange(of: self.showFileSize) { _, newValue in
						DisplayPreferences.shared.showFileSize = newValue
						self.pushUpdate(showFileSize: newValue)
					}
			}
		}
		header: {
			Text(String(localized: "appearance"))
		} footer: {
			VStack(alignment: .leading, spacing: 4) {
				Text(String(localized: "appearance-theme-footer"))
				Text(String(localized: "appearance-lyrics-font-footer"))
				Text(String(localized: "appearance-duration-footer"))
				if self.canManageFileSize {
					Text(String(localized: "appearance-file-size-footer"))
				}
			}
		}
		.task {
			await self.refreshFromServer()
		}
	}

	private func refreshFromServer() async {
		guard let server else { return }
		if let user = try? await server.send(User.me) as NafynUser {
			self.canManageFileSize = user.permissions.has(.manageMusic)
		}
		guard let settings = try? await server.send(User.appearanceSettings) as AppearanceSettings else { return }
		DisplayPreferences.shared.apply(settings)
		self.showDuration = settings.showDuration
		self.showFileSize = settings.showFileSize
	}

	private func pushUpdate(showFileSize: Bool? = nil, showDuration: Bool? = nil) {
		guard let server else { return }
		Task {
			_ = try? await server.send(User.updateAppearanceSettings(showFileSize: showFileSize, showDuration: showDuration)) as AppearanceSettings
		}
	}
}
