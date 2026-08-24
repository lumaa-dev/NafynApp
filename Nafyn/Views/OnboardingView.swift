// Made by Lumaa

import SwiftUI
import SwiftData
import Safyn
import UnionToast

struct OnboardingView: View {
	@Environment(\.modelContext) private var modelContext: ModelContext
	@Query private var existingAuths: [AuthInfo]

	@Binding var onboarding: OnboardingView.OnboardingSteps

	@State private var serverUrl: String = ""
	@State private var username: String = ""
	@State private var password: String = ""

	@State private var instance: NafynInstance? = nil

	@State private var onboardingBusy: Bool = false
	@State private var showError: Bool = false
	@State private var errorMessage: String = ""

	private var isStepCompleted: Bool {
		switch self.onboarding {
			case .welcome:
				return true
			case .server:
				return !self.serverUrl.isEmpty
			case .login:
				return !self.username.isEmpty && !self.password.isEmpty
			case .complete:
				return false
		}
	}

	init(onboarding: Binding<OnboardingView.OnboardingSteps>) {
		self._onboarding = onboarding
	}

	var body: some View {
		ZStack {
			DTColor.background
				.ignoresSafeArea()

			VStack {
				Spacer()

				VStack(alignment: .leading, spacing: 24.0) {
					VStack(alignment: .leading, spacing: 6.0) {
						onboarding.badge

						Text(onboarding.title)
							.font(DTFont.serif(31))
							.foregroundStyle(DTColor.textPrimary)
							.lineLimit(1)
							.contentTransition(.numericText(countsDown: true))
							.multilineTextAlignment(.leading)

						Text(onboarding.description)
							.font(DTFont.system(18))
							.foregroundStyle(DTColor.textPrimary)
							.multilineTextAlignment(.leading)
					}

					self.stepView
				}
				.padding(18.0)
				.background(DTColor.surfaceSelect, in: RoundedRectangle(cornerRadius: DTRadius.textArea, style: .continuous))
				.overlay(RoundedRectangle(cornerRadius: DTRadius.textArea, style: .continuous).strokeBorder(DTColor.borderSelect, lineWidth: 1))

				Spacer()

				Button {
					self.nextStep()
				} label: {
					HStack(alignment: .center, spacing: 10) {
						Text("onboarding.next")
						Image(systemName: "arrow.forward")
					}
					.frame(maxWidth: .infinity, minHeight: 20)
				}
				.disabled(self.onboardingBusy || !self.isStepCompleted)
				.buttonStyle(.filled())
				.padding(.bottom)
			}
			.padding(.horizontal)
		}
		.toast(isPresented: $showError) {
			Label(self.errorMessage, systemImage: "xmark.seal")
				.foregroundStyle(DTColor.textPrimary)
		}
	}

	@ViewBuilder
	private var stepView: some View {
		switch self.onboarding {
			case .server:
				TextField(String(localized: "server.url"), text: $serverUrl)
					.textFieldStyle(.pill)
					.textContentType(.URL)
					#if !os(macOS)
					.keyboardType(.URL)
					.textInputAutocapitalization(.never)
					#endif
					.autocorrectionDisabled()
					.submitLabel(.next)
					.onSubmit {
						guard self.isStepCompleted && !self.onboardingBusy else { return }
						self.nextStep()
					}
			case .login:
				VStack(alignment: .leading, spacing: 6.0) {
					TextField(String(localized: "username"), text: $username)
						.textFieldStyle(.pill)
						.textContentType(.username)
						#if !os(macOS)
						.keyboardType(.asciiCapable)
						.textInputAutocapitalization(.never)
						#endif
						.autocorrectionDisabled()

					SecureField(String(localized: "password"), text: $password)
						.textFieldStyle(.pill)
						.textContentType(.password)
						.submitLabel(.go)
						.onSubmit {
							guard self.isStepCompleted && !self.onboardingBusy else { return }
							self.nextStep()
						}
				}
			default:
				EmptyView()
		}
	}

	private func nextStep() {
		let allCases: [OnboardingView.OnboardingSteps] = OnboardingView.OnboardingSteps.allCases
		let curI: Int = allCases.firstIndex(of: self.onboarding) ?? 0

		Task {
			do {
				try await self.stepAction {
					withAnimation {
						self.showError = false
						self.onboarding = allCases[min(curI + 1, allCases.count - 1)]
					}
				}
			} catch {
				print("[Onboarding Error] - \(error)")
				withAnimation {
					self.errorMessage = error.localizedDescription
					self.showError = true
				}
			}
		}
	}

	private func stepAction(onSuccess: () -> Void) async throws {
		defer { withAnimation { self.onboardingBusy = false } }
		withAnimation { self.onboardingBusy = true }

		switch self.onboarding {
			case .welcome:
				onSuccess()
			case .server:
				var url: String = self.serverUrl
				if !url.starts(with: "http://") && !url.starts(with: "https://") {
					url = "https://\(url)"
				}
				while url.hasSuffix("/") {
					url.removeLast()
				}

				guard let serverUrl: URL = URL(string: url) else { throw NafynError.invalidURL }
				let instance: NafynInstance = try await NafynInstance.connect(to: serverUrl)

				self.serverUrl = url
				self.instance = instance
				onSuccess()
			case .login:
				guard let instance: NafynInstance = self.instance else { throw NafynError.invalidURL }
				let server: NafynServer = NafynServer(instance: instance)
				let response: AuthResponse = try await server.send(Auth.login(username: self.username, password: self.password))

				let auth: AuthInfo = AuthInfo(
					server: self.serverUrl,
					username: self.username,
					password: self.password,
					token: response.token,
					tokenExpire: Date.now.addingTimeInterval(60 * 60 * 24 * 7),
					defaultAuth: self.existingAuths.isEmpty
				)

				self.modelContext.insert(auth)
				try self.modelContext.save()

				UserDefaults.standard.set(true, forKey: "onboarded")
				onSuccess()
			case .complete:
				onSuccess()
		}
	}

	enum OnboardingSteps: CaseIterable, Equatable {
		case welcome
		case server
		case login
		case complete

		var title: String {
			switch self {
				case .welcome:
					"Nafyn"
				case .server:
					String(localized: "onboarding.server.title")
				case .login:
					String(localized: "onboarding.login.title")
				case .complete:
					String(localized: "onboarding.complete.title")
			}
		}

		var description: String {
			switch self {
				case .welcome:
					String(localized: "onboarding.welcome")
				case .server:
					String(localized: "onboarding.server")
				case .login:
					String(localized: "onboarding.login")
				case .complete:
					String(localized: "onboarding.complete")
			}
		}

		@ViewBuilder
		var badge: some View {
			let squareSize: CGFloat = 50.0

			ZStack {
				RoundedRectangle(cornerRadius: 14.0, style: .continuous)
					.fill(self.color)
					.frame(width: squareSize, height: squareSize)

				Image(systemName: self.symbol)
					.resizable()
					.scaledToFit()
					.frame(width: squareSize * 0.5, height: squareSize * 0.5)
					.foregroundStyle(Color.white)
			}
		}

		private var color: Color {
			switch self {
				case .welcome:
					DTColor.accentStart
				case .server:
					Color.gray
				case .login:
					Color.orange
				case .complete:
					Color.green
			}
		}

		private var symbol: String {
			switch self {
				case .welcome:
					"hand.wave.fill"
				case .server:
					"server.rack"
				case .login:
					"person.crop.square.filled.and.at.rectangle.fill"
				case .complete:
					"checkmark"
			}
		}
	}
}
