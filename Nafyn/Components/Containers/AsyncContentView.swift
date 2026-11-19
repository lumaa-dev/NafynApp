// Made by Lumaa

import SwiftUI

/// Generic loading/error/content wrapper for a single async fetch, e.g. an album/artist/track detail screen.
struct AsyncContentView<Value, Content: View>: View {
	private enum LoadState {
		case loading
		case loaded(Value)
		case failed(Error)
	}

	@State private var state: LoadState = .loading

	/// Placeholder data for the screen's skeleton (DESIGN.md "Skeleton loading"): while loading, `content` is drawn
	/// with it, redacted and disabled - the loaded screen's own shapes, toolbar included (its buttons disabled until
	/// the screen has loaded). Without one, `skeleton` is shown instead. Declared first, so it goes in the parentheses
	/// before the trailing `load` closure.
	var placeholder: Value? = nil

	let load: () async throws -> Value
	var skeleton: () -> AnyView = { AnyView(SkeletonDetailScreen()) }

	/// Paints `DTColor.background` behind loading/error/content. Set to `false` when this view is
	/// nested inside a parent that already paints its own background (e.g. `LyricsPanel`/`QueuePanel`
	/// inside `NowPlayingView`'s `CoverMeshBackground`) — otherwise this opaque fill covers it.
	var showsBackground: Bool = true

	@ViewBuilder let content: (Value, _ reload: @escaping () async -> Void) -> Content

	var body: some View {
		Group {
			switch self.state {
				case .loading:
					if let placeholder = self.placeholder {
						self.content(placeholder, {})
							.skeleton()
					} else {
						self.skeleton()
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					}
				case .loaded(let value):
					self.content(value, self.reload)
				case .failed(let error):
					VStack(spacing: 12) {
						Text(error.localizedDescription)
							.font(DTFont.system(18))
							.foregroundStyle(DTColor.textPrimary.opacity(0.7))
							.multilineTextAlignment(.center)

						Button(String(localized: "retry")) {
							Task { await self.reload() }
						}
						.buttonStyle(.hollow())
					}
					.padding()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.background {
			if self.showsBackground {
				DTColor.background.ignoresSafeArea()
			}
		}
		.task { await self.reload() }
	}

	private func reload() async {
		self.state = .loading
		do {
			let value = try await self.load()
			self.state = .loaded(value)
		} catch {
			self.state = .failed(error)
		}
	}
}
