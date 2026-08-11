import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isSigningIn = false
    @State private var statusMessage: String?
    @State private var showClientID = false
    @State private var showEmbeddedLogin = false

    var body: some View {
        @Bindable var settings = appModel.settings

        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "bookmark.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("app.name")
                    .font(.largeTitle.weight(.bold))
                Text("onboarding.subtitle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingStep(number: 1, titleKey: "onboarding.step1.title", detailKey: "onboarding.step1.detail")
                OnboardingStep(number: 2, titleKey: "onboarding.step2.title", detailKey: "onboarding.step2.detail")
                OnboardingStep(number: 3, titleKey: "onboarding.step3.title", detailKey: "onboarding.step3.detail")
            }
            .frame(maxWidth: 520)

            VStack(spacing: 12) {
                SignInWithXButton(isLoading: isSigningIn) {
                    Task { await signIn() }
                }

                Text(hasClientID ? "auth.browserLogin.caption" : "auth.signInWithX.caption")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if hasClientID {
                    Button("auth.embeddedLogin") {
                        showEmbeddedLogin = true
                    }
                    .buttonStyle(.link)
                } else {
                    Button("auth.browserLogin.needsClientID") {
                        showClientID = true
                        statusMessage = AppLocalization.text("auth.clientID.required")
                    }
                    .buttonStyle(.link)
                }

                if showClientID {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("auth.clientID.onceHelp")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("settings.xClientID", text: $settings.xClientID)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 420)
                        HStack(spacing: 12) {
                            Link("settings.openDeveloperPortal", destination: URL(string: "https://developer.x.com/en/portal/dashboard")!)
                            Text(XOAuthService.callbackURL)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 420)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .textSelection(.enabled)
                }
            }

            Button("onboarding.continueWithoutLogin") {
                appModel.settings.hasCompletedOnboarding = true
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.92),
                    Color(red: 0.93, green: 0.95, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            // Keep Client ID collapsed by default; primary login uses in-app session.
            showClientID = false
        }
        .sheet(isPresented: $showEmbeddedLogin) {
            XWebLoginSheet { result in
                Task { await handleEmbeddedLogin(result) }
            }
        }
    }

    private func handleEmbeddedLogin(_ result: Result<XWebSession, Error>) async {
        switch result {
        case .success(let session):
            switch await appModel.completeWebSignIn(session) {
            case .signedIn(let username):
                statusMessage = AppLocalization.format("settings.xConnectedAsFormat", username)
                appModel.settings.hasCompletedOnboarding = true
                appModel.selectedSidebarItem = .inbox
            case .cancelled:
                statusMessage = AppLocalization.text("oauth.error.cancelled")
            case .missingClientID:
                showClientID = true
                statusMessage = AppLocalization.text("auth.clientID.required")
            case .failed(let message):
                statusMessage = message
            }
        case .failure(let error):
            if let oauthError = error as? XOAuthError, oauthError == .cancelled {
                statusMessage = AppLocalization.text("oauth.error.cancelled")
            } else {
                statusMessage = error.localizedDescription
            }
        }
    }

    private var hasClientID: Bool {
        !appModel.settings.xClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Prefer browser OAuth when Client ID is set; otherwise open in-app login (no Client ID).
    private func signIn() async {
        if !hasClientID {
            statusMessage = nil
            showEmbeddedLogin = true
            return
        }

        isSigningIn = true
        statusMessage = AppLocalization.text("auth.browserLogin.opening")
        defer { isSigningIn = false }

        switch await appModel.signInWithXInBrowser() {
        case .signedIn(let username):
            statusMessage = AppLocalization.format("settings.xConnectedAsFormat", username)
            appModel.settings.hasCompletedOnboarding = true
            appModel.selectedSidebarItem = .inbox
        case .cancelled:
            statusMessage = AppLocalization.text("oauth.error.cancelled")
        case .missingClientID:
            showClientID = true
            showEmbeddedLogin = true
            statusMessage = AppLocalization.text("auth.clientID.required")
        case .failed(let message):
            statusMessage = message
        }
    }
}

private struct OnboardingStep: View {
    let number: Int
    let titleKey: LocalizedStringResource
    let detailKey: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.headline)
                Text(detailKey)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
