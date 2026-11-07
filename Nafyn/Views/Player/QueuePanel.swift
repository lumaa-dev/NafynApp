// Made by Lumaa

import SwiftUI
import Safyn

/// The Queue panel (DESIGN.md "Queue Panel"): one scroll view with three sections in this order -
/// 1. the song history (oldest at the top, latest at the bottom), 2. the queue actions (repeat, shuffle),
/// 3. the song queue (index `0` is the next song). It opens on the 2nd section, so scrolling up shows the history
/// and scrolling down the queue. The queue never shows the playing song nor an earlier one, and the history never
/// shows the playing song nor what is up next.
struct QueuePanel: View {
	private let actionsId = "queue-actions"

	private var engine: PlayerEngine { PlayerEngine.shared }

	/// Indices into `PlaybackSource.queue` of what plays next, in playing order.
	private var upcoming: [Int] {
		if PlaybackSource.isRemote {
			let start = PlaybackSource.currentIndex + 1
			let queue = PlaybackSource.queue
			return start >= 0 && start < queue.count ? Array(start ..< queue.count) : []
		}
		return self.engine.upcomingIndices
	}

	/// Another device's history is not shared over Nafyn Unity: only what this device played is listed.
	private var history: [MediaRow] {
		PlaybackSource.isRemote ? [] : self.engine.history
	}

	var body: some View {
		ScrollViewReader { proxy in
			List {
				if !self.history.isEmpty {
					Section {
						ForEach(Array(self.history.enumerated()), id: \.offset) { _, track in
							Button {
								self.engine.playFromHistory(track)
							} label: {
								self.row(track, highlighted: false)
							}
							.buttonStyle(.plain)
							.listRowBackground(Color.clear)
						}
					} header: {
						self.sectionTitle("queue-history")
					}
				}

				Section {
					self.actions
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				}
				.id(self.actionsId)

				Section {
					ForEach(self.upcoming, id: \.self) { index in
						let queue = PlaybackSource.queue
						if queue.indices.contains(index) {
							Button {
								if PlaybackSource.isRemote {
									UnityEngine.shared.sendCommand(.playFromQueue(index: index))
								} else {
									self.engine.playQueueIndex(index)
								}
							} label: {
								self.row(queue[index], highlighted: false)
							}
							.buttonStyle(.plain)
							.listRowBackground(Color.clear)
							.swipeActions {
								Button(role: .destructive) {
									if PlaybackSource.isRemote {
										UnityEngine.shared.sendCommand(.removeFromQueue(index: index))
									} else {
										self.engine.removeFromQueue(at: index)
									}
								} label: {
									Label(String(localized: "remove"), systemImage: "trash")
								}
								.tint(DTColor.dangerText)
							}
						}
					}
					// Unity has no reorder command, so the remote queue is not movable; neither is a shuffled one
					.onMove(perform: PlaybackSource.isRemote || self.engine.shuffleEnabled ? nil : { source, destination in
						let base = self.engine.currentIndex + 1
						self.engine.moveInQueue(
							from: IndexSet(source.map { $0 + base }),
							to: destination + base
						)
					})
				} header: {
					self.sectionTitle("playing-next")
				}
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			// the soft edge effect is the small smooth gradient on the panel's top and bottom edges
			.scrollEdgeEffectStyle(.soft, for: .all)
			.onAppear {
				proxy.scrollTo(self.actionsId, anchor: .top)
			}
		}
	}

	private func sectionTitle(_ key: LocalizedStringKey) -> some View {
		Text(key)
			.font(DTFont.system(12, weight: .semibold))
			.foregroundStyle(DTColor.textPrimary.opacity(0.5))
			.textCase(.uppercase)
	}

	private func row(_ track: MediaRow, highlighted: Bool) -> some View {
		HStack(spacing: 10) {
			CoverImage(url: track.highResCoverURL, cornerRadius: 6)
				.frame(width: 44, height: 44)

			VStack(alignment: .leading, spacing: 2) {
				Text(track.title)
					.font(DTFont.serif(18))
					.foregroundStyle(highlighted ? DTColor.accentStart : DTColor.textPrimary)
					.lineLimit(1)
				Text(track.artistName)
					.font(DTFont.serif(15))
					.foregroundStyle(DTColor.textPrimary.opacity(0.5))
					.lineLimit(1)
			}
			Spacer()
		}
		.contentShape(.rect)
	}

	// MARK: - Queue actions

	/// Repeat and shuffle, the same height and the same width whatever the label.
	private var actions: some View {
		HStack(spacing: 10) {
			self.repeatButton
			self.shuffleButton
		}
	}

	private var repeatMode: RepeatMode {
		PlaybackSource.isRemote
			? RepeatMode(wireValue: UnityEngine.shared.remoteState?.repeatMode ?? "off")
			: self.engine.repeatMode
	}

	@ViewBuilder
	private var repeatButton: some View {
		let mode = self.repeatMode
		let symbol = mode == .track ? "repeat.1" : "repeat"

		if mode == .off {
			Button { self.cycleRepeat() } label: {
				Label("Repeat", systemImage: symbol).frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
		} else {
			Button { self.cycleRepeat() } label: {
				Label("Repeat", systemImage: symbol).frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())
		}
	}

	@ViewBuilder
	private var shuffleButton: some View {
		if PlaybackSource.isRemote {
			// the master reshuffles what is up next, once (a Nafyn Unity command every Nafyn player knows)
			Button {
				UnityEngine.shared.sendCommand(.custom(action: "shuffleQueue", payload: []))
			} label: {
				Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
			.disabled(self.upcoming.count < 2)
		} else if self.engine.shuffleEnabled {
			Button { self.engine.toggleShuffle() } label: {
				Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
			}
			.buttonStyle(.filled())
		} else {
			Button { self.engine.toggleShuffle() } label: {
				Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
			}
			.buttonStyle(.hollow())
		}
	}

	private func cycleRepeat() {
		if PlaybackSource.isRemote {
			UnityEngine.shared.sendCommand(.cycleRepeat)
		} else {
			self.engine.repeatMode = self.engine.repeatMode.next
		}
	}
}
