// Made by Lumaa

import SwiftUI
import Safyn

/// Which set of webhooks a ``WebhooksSettingsSection`` manages: the signed-in user's own, or the
/// instance-wide ones (needs `MANAGE_WEBHOOKS`, request events only).
enum WebhookScope {
	case personal
	case global

	/// Global webhooks only fire for request events; `release.out` is per-user.
	var availableEvents: [WebhookEvent] {
		switch self {
			case .personal:
				[.requestCreated, .requestAccepted, .requestDenied, .requestCompleted, .requestFailed, .releaseOut]
			case .global:
				[.requestCreated, .requestAccepted, .requestDenied, .requestCompleted, .requestFailed]
		}
	}
}

extension WebhookEvent {
	var label: String {
		switch self {
			case .requestCreated: String(localized: "event-request-created")
			case .requestAccepted: String(localized: "event-request-accepted")
			case .requestDenied: String(localized: "event-request-denied")
			case .requestCompleted: String(localized: "event-request-completed")
			case .requestFailed: String(localized: "event-request-failed")
			case .releaseOut: String(localized: "event-release-out")
		}
	}
}

extension WebhookFormat {
	var label: String {
		switch self {
			case .auto: String(localized: "webhook-format-auto")
			case .discord: String("Discord")
			case .slack: String("Slack")
			case .ntfy: String("ntfy")
			case .gotify: String("Gotify")
			case .json: String("JSON")
		}
	}
}

/// Loads and mutates one scope of webhooks. The personal and global endpoints are separate `NafynEndpoint`
/// enums with the same shape, so this is the one place that switches between them.
@Observable
final class WebhookStore {
	let scope: WebhookScope

	private(set) var webhooks: [WebhookSummary] = []
	private(set) var isLoaded = false

	init(scope: WebhookScope) {
		self.scope = scope
	}

	func load(server: NafynServer) async throws {
		switch self.scope {
			case .personal:
				self.webhooks = try await server.send(User.webhooks)
			case .global:
				self.webhooks = try await server.send(Settings.webhooks)
		}
		self.isLoaded = true
	}

	func create(server: NafynServer, name: String, url: String, format: WebhookFormat, events: [WebhookEvent]?) async throws {
		// every event selected is stored as `null` ("all events"), so events added later are included too
		let patch: Patchable<[WebhookEvent]> = events.map { .value($0) } ?? .clear
		let created: WebhookSummary
		switch self.scope {
			case .personal:
				created = try await server.send(User.createWebhook(name: name, url: url, format: format, events: patch, enabled: true))
			case .global:
				created = try await server.send(Settings.createWebhook(name: name, url: url, format: format, events: patch, enabled: true))
		}
		self.webhooks.append(created)
	}

	func setEnabled(server: NafynServer, webhook: WebhookSummary, enabled: Bool) async throws {
		let updated: WebhookSummary
		switch self.scope {
			case .personal:
				updated = try await server.send(User.updateWebhook(id: webhook.id, enabled: enabled))
			case .global:
				updated = try await server.send(Settings.updateWebhook(id: webhook.id, enabled: enabled))
		}
		self.replace(updated)
	}

	func test(server: NafynServer, webhook: WebhookSummary) async throws -> WebhookTestResponse {
		let result: WebhookTestResponse
		switch self.scope {
			case .personal:
				result = try await server.send(User.testWebhook(id: webhook.id))
			case .global:
				result = try await server.send(Settings.testWebhook(id: webhook.id))
		}
		// the test updates delivery stats server-side; pick them up
		try? await self.load(server: server)
		return result
	}

	func delete(server: NafynServer, webhook: WebhookSummary) async throws {
		switch self.scope {
			case .personal:
				_ = try await server.sendRaw(User.deleteWebhook(id: webhook.id))
			case .global:
				_ = try await server.sendRaw(Settings.deleteWebhook(id: webhook.id))
		}
		self.webhooks.removeAll(where: { $0.id == webhook.id })
	}

	private func replace(_ webhook: WebhookSummary) {
		guard let index = self.webhooks.firstIndex(where: { $0.id == webhook.id }) else { return }
		self.webhooks[index] = webhook
	}
}

/// The webhook manager: a list of webhooks (enable, test, delete) and an "Add webhook" sheet. Used both for
/// the user's own webhooks (Settings → Notifications) and the instance's (Settings → Webhooks).
struct WebhooksSettingsSection: View {
	@Environment(\.server) private var server: NafynServer?

	@State private var store: WebhookStore
	@State private var toast = ToastState()
	@State private var isAdding = false
	@State private var loadError: Error? = nil
	@State private var busyIds: Set<String> = []

	init(scope: WebhookScope) {
		self._store = State(initialValue: WebhookStore(scope: scope))
	}

	private var title: String {
		self.store.scope == .personal ? String(localized: "your-webhooks") : String(localized: "webhooks")
	}

	var body: some View {
		Section {
			if let loadError, !self.store.isLoaded {
				Text(loadError.localizedDescription)
					.foregroundStyle(DTColor.statusFailure)
			}

			ForEach(self.store.webhooks) { webhook in
				self.row(webhook)
			}

			Button {
				self.isAdding = true
			} label: {
				Label(String(localized: "add-webhook"), systemImage: "plus")
			}
			.disabled(NetworkMonitor.shared.isOffline)
		} header: {
			Text(self.title)
		}
		.task {
			guard let server, !self.store.isLoaded else { return }
			do {
				try await self.store.load(server: server)
			} catch {
				self.loadError = error
			}
		}
		.sheet(isPresented: self.$isAdding) {
			AddWebhookSheet(scope: self.store.scope) { name, url, format, events in
				guard let server else { return }
				try await self.store.create(server: server, name: name, url: url, format: format, events: events)
			}
		}
		.toast(self.toast)
	}

	@ViewBuilder
	private func row(_ webhook: WebhookSummary) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline) {
				Text(webhook.name)
					.foregroundStyle(DTColor.textPrimary)
					.lineLimit(1)

				Text(webhook.format.label)
					.font(DTFont.system(12, weight: .semibold))
					.padding(.horizontal, 7)
					.padding(.vertical, 2)
					.background(DTColor.surfaceInput, in: Capsule())
					.foregroundStyle(DTColor.textPrimary.opacity(0.7))

				Spacer(minLength: 0)

				Toggle(webhook.name, isOn: Binding(
					get: { webhook.enabled },
					set: { self.setEnabled(webhook, $0) }
				))
				.labelsHidden()
				.disabled(self.busyIds.contains(webhook.id) || NetworkMonitor.shared.isOffline)
			}

			// only the scheme + host: the full URL is a secret the server never returns again
			Text(webhook.urlPreview)
				.font(.system(.footnote, design: .monospaced))
				.foregroundStyle(DTColor.textPrimary.opacity(0.55))
				.lineLimit(1)

			Text(self.eventSummary(webhook))
				.font(DTFont.text(.footnote))
				.foregroundStyle(DTColor.textPrimary.opacity(0.55))

			if let delivered = webhook.lastDeliveredAtDate {
				Text("webhook-last-delivered \(delivered.formatted(.relative(presentation: .named)))")
					.font(DTFont.text(.footnote))
					.foregroundStyle(DTColor.textPrimary.opacity(0.55))
			}

			if let failure = self.failureText(webhook) {
				Text(failure)
					.font(DTFont.text(.footnote))
					.foregroundStyle(DTColor.statusFailure)
			}

			HStack(spacing: 16) {
				Button(String(localized: "test")) {
					self.test(webhook)
				}
				.disabled(self.busyIds.contains(webhook.id) || NetworkMonitor.shared.isOffline)

				Button(String(localized: "delete"), role: .destructive) {
					self.delete(webhook)
				}
				.tint(DTColor.dangerText)
				.disabled(self.busyIds.contains(webhook.id) || NetworkMonitor.shared.isOffline)
			}
			.buttonStyle(.borderless)
			.font(DTFont.text(.subheadline))
		}
		.padding(.vertical, 4)
		.swipeActions {
			Button(role: .destructive) {
				self.delete(webhook)
			} label: {
				Label(String(localized: "delete"), systemImage: "trash")
			}
			.tint(DTColor.dangerText)
		}
	}

	private func eventSummary(_ webhook: WebhookSummary) -> String {
		guard let events = webhook.events else { return String(localized: "all-events") }
		return events.map(\.label).joined(separator: ", ")
	}

	private func failureText(_ webhook: WebhookSummary) -> String? {
		guard webhook.failureCount > 0 else { return nil }
		let reason = webhook.lastError ?? String()

		if !webhook.enabled {
			return String(localized: "webhook-switched-off \(reason)")
		}
		return String(localized: "webhook-failing \(webhook.failureCount) \(reason)")
	}

	private func setEnabled(_ webhook: WebhookSummary, _ enabled: Bool) {
		self.perform(webhook) { server in
			try await self.store.setEnabled(server: server, webhook: webhook, enabled: enabled)
		}
	}

	private func test(_ webhook: WebhookSummary) {
		self.perform(webhook) { server in
			let result = try await self.store.test(server: server, webhook: webhook)
			if result.ok {
				self.toast.success(String(localized: "webhook-test-ok"))
			} else {
				self.toast.failure(WebhookTestError(message: result.error ?? String(localized: "webhook-test-failed")))
			}
		}
	}

	private func delete(_ webhook: WebhookSummary) {
		self.perform(webhook) { server in
			try await self.store.delete(server: server, webhook: webhook)
		}
	}

	private func perform(_ webhook: WebhookSummary, _ work: @escaping (NafynServer) async throws -> Void) {
		guard let server, !self.busyIds.contains(webhook.id) else { return }
		self.busyIds.insert(webhook.id)

		Task {
			defer { self.busyIds.remove(webhook.id) }
			do {
				try await work(server)
			} catch {
				self.toast.failure(error)
			}
		}
	}
}

private struct WebhookTestError: LocalizedError {
	let message: String
	var errorDescription: String? { self.message }
}

/// The create form. The URL is typed once here and never shown again — the server only returns a preview.
private struct AddWebhookSheet: View {
	@Environment(\.dismiss) private var dismiss

	let scope: WebhookScope
	let onAdd: (_ name: String, _ url: String, _ format: WebhookFormat, _ events: [WebhookEvent]?) async throws -> Void

	@State private var name = ""
	@State private var url = ""
	@State private var format: WebhookFormat = .auto
	@State private var selected: Set<WebhookEvent>
	@State private var isSaving = false
	@State private var toast = ToastState()

	init(scope: WebhookScope, onAdd: @escaping (String, String, WebhookFormat, [WebhookEvent]?) async throws -> Void) {
		self.scope = scope
		self.onAdd = onAdd
		self._selected = State(initialValue: Set(scope.availableEvents))
	}

	private static let formats: [WebhookFormat] = [.auto, .discord, .slack, .ntfy, .gotify, .json]

	private var canAdd: Bool {
		!self.name.trimmingCharacters(in: .whitespaces).isEmpty
			&& !self.url.trimmingCharacters(in: .whitespaces).isEmpty
			&& !self.selected.isEmpty
			&& !self.isSaving
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(String(localized: "webhook-name"), text: self.$name)
					TextField(String(localized: "webhook-url"), text: self.$url)
						.textContentType(.URL)
						.keyboardType(.URL)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				} footer: {
					Text("webhook-url-footer")
				}
				.sheetRows()

				Section {
					Picker(String(localized: "webhook-format"), selection: self.$format) {
						ForEach(Self.formats, id: \.self) { format in
							Text(format.label).tag(format)
						}
					}
				}
				.sheetRows()

				Section(String(localized: "webhook-events")) {
					ForEach(self.scope.availableEvents, id: \.self) { event in
						Toggle(event.label, isOn: Binding(
							get: { self.selected.contains(event) },
							set: { isOn in
								if isOn { self.selected.insert(event) } else { self.selected.remove(event) }
							}
						))
					}
				}
				.sheetRows()
			}
			.scrollContentBackground(.hidden)
			.background(DTColor.background.ignoresSafeArea())
			.navigationTitle(String(localized: "add-webhook"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						self.dismiss()
					} label: {
						Label(String(localized: "cancel"), systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.primary)
				}

				ToolbarItem(placement: .confirmationAction) {
					Button {
						self.add()
					} label: {
						Label(String(localized: "add"), systemImage: "checkmark")
							.labelStyle(.iconOnly)
					}
					.tint(Color.accentColor)
					.disabled(!self.canAdd)
				}
			}
			.toast(self.toast)
		}
		.sheetBackground()
	}

	private func add() {
		self.isSaving = true
		let all = Set(self.scope.availableEvents)
		// every event ticked means "all events"
		let events: [WebhookEvent]? = self.selected == all ? nil : self.scope.availableEvents.filter { self.selected.contains($0) }

		Task {
			defer { self.isSaving = false }
			do {
				try await self.onAdd(self.name.trimmingCharacters(in: .whitespaces), self.url.trimmingCharacters(in: .whitespaces), self.format, events)
				self.dismiss()
			} catch {
				// the server is the authority on URL rules (https, default port, public address): show its message
				self.toast.failure(error)
			}
		}
	}
}

/// Settings → Webhooks (needs `MANAGE_WEBHOOKS`): the instance-wide webhooks.
struct InstanceWebhooksSettingsSection: View {
	var body: some View {
		Section {
			Text("webhooks-global-intro")
				.font(DTFont.text(.footnote))
				.foregroundStyle(DTColor.textPrimary.opacity(0.6))
		}

		WebhooksSettingsSection(scope: .global)
	}
}
