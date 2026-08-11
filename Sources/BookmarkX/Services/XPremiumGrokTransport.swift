import Foundation

/// Uses X Premium Grok quota via the signed-in X web session (preferred),
/// with OAuth access-token fallback when available.
struct XPremiumGrokTransport: Sendable {
    var accessToken: String?
    var webSession: XWebSession?
    var username: String?
    var model: String
    var outputLanguage: AppLanguage
    var session: URLSession = .shared

    func enrich(
        tweetText: String,
        authorUsername: String?,
        existingFolders: [String] = []
    ) async throws -> GrokPayload {
        if let webSession {
            do {
                return try await XWebSessionClient(session: session).enrichWithPremiumGrok(
                    session: webSession,
                    tweetText: tweetText,
                    authorUsername: authorUsername,
                    outputLanguage: outputLanguage,
                    model: preferredPremiumModel,
                    existingFolders: existingFolders
                )
            } catch {
                // Fall through to OAuth token attempt if present.
                if accessToken == nil {
                    throw GrokError.premiumUnavailable(error.localizedDescription)
                }
            }
        }

        guard let accessToken, !accessToken.isEmpty else {
            throw GrokError.premiumRequiresX
        }

        do {
            return try await XAIAPITransport(
                apiKey: accessToken,
                model: preferredPremiumModel,
                outputLanguage: outputLanguage,
                session: session
            ).enrich(
                tweetText: tweetText,
                authorUsername: authorUsername,
                existingFolders: existingFolders
            )
        } catch GrokError.server(let statusCode, let message) where [401, 403, 404].contains(statusCode) {
            throw GrokError.premiumUnavailable(
                String(
                    format: String(localized: "grok.error.premiumRejectedFormat"),
                    "HTTP \(statusCode): \(message)"
                )
            )
        }
    }

    private var preferredPremiumModel: String {
        if model.lowercased().contains("grok") {
            return model
        }
        return "grok-4-fast"
    }
}
