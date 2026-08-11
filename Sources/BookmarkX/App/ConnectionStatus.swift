import Foundation
import Observation

@Observable
@MainActor
final class ConnectionStatus {
    private let credentialStore: KeychainStore

    var isXConnected = false
    var isGrokConfigured = false
    var grokStatusKey: LocalizedStringResource = "status.grokMissing"
    var activeGrokMode: GrokAccessMode?
    var xUsername: String?
    var authMethod: XAuthMethod?

    init(credentialStore: KeychainStore = .shared) {
        self.credentialStore = credentialStore
    }

    func refresh(from settings: AppSettings) {
        let store = credentialStore
        let accessToken = try? store.load(.xAccessToken)
        let authCookie = try? store.load(.xAuthCookie)
        let apiKey = try? store.load(.grokAPIKey)
        let methodRaw = try? store.load(.xAuthMethod)

        isXConnected = (accessToken?.isEmpty == false) || (authCookie?.isEmpty == false)
        xUsername = try? store.load(.xUsername)
        authMethod = methodRaw.flatMap(XAuthMethod.init(rawValue:))

        switch settings.grokAccessMode {
        case .xPremium:
            isGrokConfigured = isXConnected
            activeGrokMode = isXConnected ? .xPremium : nil
            grokStatusKey = isXConnected ? "status.grokPremiumReady" : "status.grokPremiumMissing"
        case .apiKey:
            isGrokConfigured = apiKey?.isEmpty == false
            activeGrokMode = isGrokConfigured ? .apiKey : nil
            grokStatusKey = isGrokConfigured ? "status.grokAPIKeyReady" : "status.grokAPIKeyMissing"
        case .auto:
            if isXConnected {
                isGrokConfigured = true
                activeGrokMode = .xPremium
                grokStatusKey = apiKey?.isEmpty == false
                    ? "status.grokAutoPremiumWithFallback"
                    : "status.grokAutoPremium"
            } else if apiKey?.isEmpty == false {
                isGrokConfigured = true
                activeGrokMode = .apiKey
                grokStatusKey = "status.grokAutoAPIKey"
            } else {
                isGrokConfigured = false
                activeGrokMode = nil
                grokStatusKey = "status.grokAutoMissing"
            }
        }
    }
}
