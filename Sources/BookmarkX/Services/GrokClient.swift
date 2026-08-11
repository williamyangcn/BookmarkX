import Foundation

struct GrokEnrichment: Sendable, Equatable {
    var title: String
    var summary: String
    var category: String
    var tags: [String]
    var model: String
    var provider: GrokAccessMode
}

enum GrokError: LocalizedError {
    case notConfigured(GrokAccessMode)
    case premiumRequiresX
    case apiKeyMissing
    case invalidResponse
    case server(statusCode: Int, message: String)
    case decodingFailed
    case emptyContent
    case premiumUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let mode):
            switch mode {
            case .xPremium:
                String(localized: "grok.error.premiumNotReady")
            case .apiKey:
                String(localized: "grok.error.apiKeyMissing")
            case .auto:
                String(localized: "grok.error.autoNotReady")
            }
        case .premiumRequiresX:
            String(localized: "grok.error.premiumRequiresX")
        case .apiKeyMissing:
            String(localized: "grok.error.apiKeyMissing")
        case .invalidResponse:
            String(localized: "grok.error.invalidResponse")
        case .server(let statusCode, let message):
            "Grok \(statusCode): \(message)"
        case .decodingFailed:
            String(localized: "grok.error.decodingFailed")
        case .emptyContent:
            String(localized: "grok.error.emptyContent")
        case .premiumUnavailable(let message):
            message
        }
    }
}

/// Resolves which Grok backend to use and performs bookmark enrichment.
actor GrokClient {
    struct Snapshot: Sendable {
        var mode: GrokAccessMode
        var model: String
        var outputLanguage: AppLanguage
        var isXConnected: Bool
        var apiKey: String?
        var xAccessToken: String?
        var webSession: XWebSession?
        var xUsername: String?
    }

    private var snapshot = Snapshot(
        mode: .xPremium,
        model: "grok-4-fast",
        outputLanguage: .simplifiedChinese,
        isXConnected: false,
        apiKey: nil,
        xAccessToken: nil,
        webSession: nil,
        xUsername: nil
    )

    func configure(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func preferredProvider() -> GrokAccessMode? {
        switch snapshot.mode {
        case .xPremium:
            return snapshot.isXConnected ? .xPremium : nil
        case .apiKey:
            return hasAPIKey ? .apiKey : nil
        case .auto:
            if snapshot.isXConnected {
                return .xPremium
            }
            if hasAPIKey {
                return .apiKey
            }
            return nil
        }
    }

    func isConfigured() -> Bool {
        switch snapshot.mode {
        case .xPremium:
            return snapshot.isXConnected
        case .apiKey:
            return hasAPIKey
        case .auto:
            return snapshot.isXConnected || hasAPIKey
        }
    }

    func enrich(
        tweetText: String,
        authorUsername: String? = nil,
        existingFolders: [String] = []
    ) async throws -> GrokEnrichment {
        switch snapshot.mode {
        case .xPremium:
            return try await enrichWithXPremium(
                tweetText: tweetText,
                authorUsername: authorUsername,
                existingFolders: existingFolders
            )
        case .apiKey:
            return try await enrichWithAPIKey(
                tweetText: tweetText,
                authorUsername: authorUsername,
                existingFolders: existingFolders
            )
        case .auto:
            if snapshot.isXConnected {
                do {
                    return try await enrichWithXPremium(
                        tweetText: tweetText,
                        authorUsername: authorUsername,
                        existingFolders: existingFolders
                    )
                } catch {
                    if hasAPIKey {
                        return try await enrichWithAPIKey(
                            tweetText: tweetText,
                            authorUsername: authorUsername,
                            existingFolders: existingFolders
                        )
                    }
                    throw error
                }
            }
            return try await enrichWithAPIKey(
                tweetText: tweetText,
                authorUsername: authorUsername,
                existingFolders: existingFolders
            )
        }
    }

    private var hasAPIKey: Bool {
        snapshot.apiKey?.isEmpty == false
    }

    private func enrichWithAPIKey(
        tweetText: String,
        authorUsername: String?,
        existingFolders: [String]
    ) async throws -> GrokEnrichment {
        guard let apiKey = snapshot.apiKey, !apiKey.isEmpty else {
            throw GrokError.apiKeyMissing
        }

        let payload = try await XAIAPITransport(
            apiKey: apiKey,
            model: snapshot.model,
            outputLanguage: snapshot.outputLanguage
        ).enrich(
            tweetText: tweetText,
            authorUsername: authorUsername,
            existingFolders: existingFolders
        )

        return GrokEnrichment(
            title: payload.title,
            summary: payload.summary,
            category: payload.category,
            tags: payload.tags,
            model: snapshot.model,
            provider: .apiKey
        )
    }

    private func enrichWithXPremium(
        tweetText: String,
        authorUsername: String?,
        existingFolders: [String]
    ) async throws -> GrokEnrichment {
        guard snapshot.isXConnected else {
            throw GrokError.premiumRequiresX
        }

        let payload = try await XPremiumGrokTransport(
            accessToken: snapshot.xAccessToken,
            webSession: snapshot.webSession,
            username: snapshot.xUsername,
            model: snapshot.model,
            outputLanguage: snapshot.outputLanguage
        ).enrich(
            tweetText: tweetText,
            authorUsername: authorUsername,
            existingFolders: existingFolders
        )

        return GrokEnrichment(
            title: payload.title,
            summary: payload.summary,
            category: payload.category,
            tags: payload.tags,
            model: payload.model ?? snapshot.model,
            provider: .xPremium
        )
    }
}
