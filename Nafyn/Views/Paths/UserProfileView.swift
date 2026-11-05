// Made by Lumaa

import SwiftUI
import Safyn

/// The signed-in user's own profile page: avatar, names, linked Last.fm / Discogs accounts, library size and
/// public playlists, from `Users.profile(username:)` (what everyone else sees of them). "Edit" opens
/// ``ProfileEditSheet``.
struct UserProfileView: View {
	@Environment(\.server) private var server: NafynServer?

	private struct Loaded {
		let user: NafynUser
		let profile: UserProfile
	}

	var body: some View {
		AsyncContentView {
			guard let server else { throw NafynError.unauthenticated }
			let user: NafynUser = try await server.send(User.me)
			let profile: UserProfile = try await server.send(Users.profile(username: user.username))
			return Loaded(user: user, profile: profile)
		} content: { loaded, _ in
			UserProfileContent(user: loaded.user, profile: loaded.profile)
		}
		.navigationTitle(String(localized: "profile"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct UserProfileContent: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var user: NafynUser
	@State private var profile: UserProfile
	@State private var showEdit = false

	init(user: NafynUser, profile: UserProfile) {
		self._user = State(initialValue: user)
		self._profile = State(initialValue: profile)
	}

	var body: some View {
		AdaptiveDetail {
			VStack(alignment: .leading, spacing: 24) {
				self.header
				self.playlists
			}
		} primary: {
			self.header
		} secondary: {
			self.playlists
		}
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					self.showEdit = true
				} label: {
					Label(String(localized: "edit"), systemImage: "pencil")
						.labelStyle(.iconOnly)
				}
				.tint(Color.primary)
				.disabled(NetworkMonitor.shared.isOffline)
			}
		}
		.sheet(isPresented: self.$showEdit) {
			ProfileEditSheet(user: self.user) { updated in
				self.apply(updated)
			}
		}
	}

	/// Avatar, names, library size and linked accounts.
	@ViewBuilder
	private var header: some View {
		VStack(spacing: 10) {
			Group {
				if let url = self.server?.avatarURL(userId: self.profile.id, version: self.profile.avatar) {
					CoverImage(url: url, cornerRadius: 0)
				} else {
					Image(systemName: "person.crop.circle.fill")
						.resizable()
						.scaledToFit()
						.foregroundStyle(DTColor.textPrimary.opacity(0.35))
				}
			}
			.clipShape(Circle())
			.frame(width: 140, height: 140)

			Text(self.profile.displayName ?? self.profile.username)
				.font(DTFont.serif(31))
				.foregroundStyle(DTColor.textPrimary)
				.multilineTextAlignment(.center)

			Text("@\(self.profile.username)")
				.font(DTFont.system(16))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

			Text("\(self.profile.trackCount) " + String(localized: "tracks"))
				.font(DTFont.system(16))
				.foregroundStyle(DTColor.textPrimary.opacity(0.5))

			HStack(spacing: 16) {
				if let lastFm = self.profile.lastFm, !lastFm.isEmpty, let url = URL(string: "https://www.last.fm/user/\(lastFm)") {
					Link(String("Last.fm"), destination: url)
				}
				if let discogs = self.profile.discogs, !discogs.isEmpty, let url = URL(string: "https://www.discogs.com/user/\(discogs)") {
					Link(String("Discogs"), destination: url)
				}
			}
			.font(DTFont.system(16))
			.tint(Color.primary)
		}
		.frame(maxWidth: .infinity)
	}

	/// The public playlists, as everybody else sees them.
	@ViewBuilder
	private var playlists: some View {
		if !self.profile.playlists.isEmpty {
			VStack(alignment: .leading, spacing: 16) {
				Text("playlists")
					.font(DTFont.serifItalic(25))
					.foregroundStyle(DTColor.textPrimary)

				LazyVStack(spacing: 12) {
					ForEach(self.profile.playlists) { playlist in
						NavigationLink(value: Navigator.Paths.playlist(id: playlist.id)) {
							self.row(playlist)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
	}

	private func row(_ playlist: UserProfile.PlaylistSummary) -> some View {
		HStack(spacing: 12) {
			CoverImage(url: playlist.image == nil ? nil : MusicCardEntry.playlistImageURL(pid: playlist.id, server: self.server))
				.frame(width: 60, height: 60)

			VStack(alignment: .leading, spacing: 2) {
				Text(playlist.title)
					.font(DTFont.serif(18))
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(2)
					.multilineTextAlignment(.leading)

				Text("\(playlist.trackCount) " + String(localized: "tracks"))
					.font(DTFont.serif(16))
					.foregroundStyle(DTColor.textPrimary.opacity(0.6))
			}

			Spacer(minLength: 0)
		}
		.contentShape(Rectangle())
	}

	/// What the edit sheet saved, shown right away instead of reloading the screen (which would close the sheet).
	private func apply(_ updated: NafynUser) {
		self.user = updated
		self.profile = UserProfile(
			id: updated.id,
			username: updated.username,
			displayName: updated.displayName,
			avatar: updated.avatar,
			lastFm: updated.lastFm,
			discogs: updated.discogs,
			trackCount: self.profile.trackCount,
			playlists: self.profile.playlists
		)
	}
}
