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

	let load: () async throws -> Value
	var skeleton: () -> AnyView = { AnyView(SkeletonDetailScreen()) }
	@ViewBuilder let content: (Value, _ reload: @escaping () async -> Void) -> Content

	var body: some View {
		Group {
			switch self.state {
				case .loading:
					self.skeleton()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
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
		.background(DTColor.background.ignoresSafeArea())
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
