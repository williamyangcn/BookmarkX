import Foundation
import WebKit

@MainActor
extension AppModel {
    enum XSignInOutcome: Equatable {
        case signedIn(username: String)
        case cancelled
        case missingClientID
        case failed(String)
    }

    /// Opens the default browser for X login (Google / Apple / passkeys supported).
    func signInWithXInBrowser() async -> XSignInOutcome {
        let clientID = settings.xClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            return .missingClientID
        }

        do {
            let user = try await xOAuthService.authenticateInDefaultBrowser(clientID: clientID)
            settings.grokAccessMode = .xPremium
            settings.hasCompletedOnboarding = true
            connectionStatus.refresh(from: settings)
            await configureGrokClient()
            return .signedIn(username: user.username)
        } catch let error as XOAuthError where error == .cancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func completeWebSignIn(_ session: XWebSession) async -> XSignInOutcome {
        do {
            try XWebSessionStore.save(session)
            await XWebCookieBridge.apply(
                session: session,
                to: WKWebsiteDataStore.default().httpCookieStore
            )
            settings.grokAccessMode = .xPremium
            settings.hasCompletedOnboarding = true
            connectionStatus.refresh(from: settings)
            await configureGrokClient()
            let username = session.username ?? (try? KeychainStore.shared.load(.xUsername)) ?? "x-user"
            return .signedIn(username: username)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Inject saved X cookies into the shared WKWebView store (used by post preview).
    func seedPreviewWebSession() async {
        await XWebCookieBridge.applySavedSession(
            to: XWebCookieBridge.previewDataStore.httpCookieStore
        )
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        XOAuthCallbackHub.handle(url: url)
    }

    func signOutX() {
        XOAuthCallbackHub.cancel()
        try? KeychainStore.shared.clearXCredentials()
        settings.resetSyncProgress()
        connectionStatus.refresh(from: settings)
        Task {
            await XWebCookieBridge.clearSessionData()
            await configureGrokClient()
        }
    }

    func clearAllCredentials() {
        XOAuthCallbackHub.cancel()
        try? KeychainStore.shared.clearAll()
        settings.resetSyncProgress()
        connectionStatus.refresh(from: settings)
        Task {
            await XWebCookieBridge.clearSessionData()
            await configureGrokClient()
        }
    }
}
