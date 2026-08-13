import Foundation

/// Premium Grok via the signed-in X web session only.
/// Never send an X OAuth access token to api.x.ai — that is not an xAI API key.
struct XPremiumGrokTransport: Sendable {
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
        guard let webSession else {
            throw GrokError.premiumRequiresX
        }

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
            throw GrokError.premiumUnavailable(error.localizedDescription)
        }
    }

    private var preferredPremiumModel: String {
        if model.lowercased().contains("grok") {
            return model
        }
        return "grok-4-fast"
    }
}
