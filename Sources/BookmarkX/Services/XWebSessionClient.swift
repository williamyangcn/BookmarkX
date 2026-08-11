import Foundation

/// X web session credentials (same style as signing into Grok / x.com in a browser).
struct XWebSession: Sendable, Equatable {
    var authToken: String
    var ct0: String
    var userID: String?
    var username: String?
    var name: String?

    var cookieHeader: String {
        "auth_token=\(authToken); ct0=\(ct0)"
    }
}

enum XWebSessionError: LocalizedError {
    case missingCookies
    case invalidResponse
    case server(statusCode: Int, message: String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingCookies:
            String(localized: "auth.session.missingCookies")
        case .invalidResponse:
            String(localized: "auth.session.invalidResponse")
        case .server(let statusCode, let message):
            "X \(statusCode): \(message)"
        case .notSignedIn:
            String(localized: "auth.session.notSignedIn")
        }
    }
}

enum XWebSessionStore {
    static func save(_ session: XWebSession) throws {
        let keychain = KeychainStore.shared
        try keychain.save(session.authToken, for: .xAuthCookie)
        try keychain.save(session.ct0, for: .xCT0)
        try keychain.save(XAuthMethod.webSession.rawValue, for: .xAuthMethod)
        if let userID = session.userID {
            try keychain.save(userID, for: .xUserID)
        }
        if let username = session.username {
            try keychain.save(username, for: .xUsername)
        }
    }

    static func load() throws -> XWebSession? {
        let keychain = KeychainStore.shared
        guard
            let authToken = try keychain.load(.xAuthCookie), !authToken.isEmpty,
            let ct0 = try keychain.load(.xCT0), !ct0.isEmpty
        else {
            return nil
        }
        return XWebSession(
            authToken: authToken,
            ct0: ct0,
            userID: try keychain.load(.xUserID),
            username: try keychain.load(.xUsername),
            name: nil
        )
    }
}

/// Talks to X/Grok using the browser session from “Sign in with X”.
actor XWebSessionClient {
    /// Public guest bearer used by x.com web clients.
    static let publicBearer =
        "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(session webSession: XWebSession) async throws -> XWebSession {
        var request = URLRequest(url: URL(string: "https://api.x.com/1.1/account/verify_credentials.json")!)
        applyWebAuth(to: &request, session: webSession)

        let (data, response) = try await self.session.data(for: request)
        try Self.validate(response: response, data: data)

        let user = try JSONDecoder().decode(VerifyUser.self, from: data)
        var updated = webSession
        updated.userID = String(user.id)
        updated.username = user.screenName
        updated.name = user.name
        return updated
    }

    func enrichWithPremiumGrok(
        session webSession: XWebSession,
        tweetText: String,
        authorUsername: String?,
        outputLanguage: AppLanguage,
        model: String
    ) async throws -> GrokPayload {
        let languageInstruction: String = switch outputLanguage {
        case .english: "Respond in English."
        case .simplifiedChinese: "用简体中文回答。"
        case .system: "Match the language of the tweet when possible; otherwise use Simplified Chinese."
        }

        let authorLine = authorUsername.map { "Author: @\($0)\n" } ?? ""
        let prompt = """
        \(authorLine)Tweet:
        \(tweetText)

        \(languageInstruction)
        Return JSON only with keys title, summary, category, tags.
        title must be concise; tags must contain 1-5 short reusable tags.
        """

        // Grok web (X Premium) entry points.
        // 1) create conversation  2) add response
        let conversationID = try await createConversation(session: webSession)
        let content = try await addResponse(
            session: webSession,
            conversationID: conversationID,
            prompt: prompt,
            model: model
        )
        return try Self.parsePayload(from: content, model: model)
    }

    private func createConversation(session webSession: XWebSession) async throws -> String {
        let url = URL(string: "https://grok.x.com/2/create-conversation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyWebAuth(to: &request, session: webSession)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "conversation": [
                "messages": []
            ]
        ])

        let (data, response) = try await self.session.data(for: request)
        try Self.validate(response: response, data: data)

        if
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let conversationID = object["conversation_id"] as? String
                ?? (object["conversation"] as? [String: Any])?["conversation_id"] as? String
                ?? object["id"] as? String
        {
            return conversationID
        }

        throw XWebSessionError.invalidResponse
    }

    private func addResponse(
        session webSession: XWebSession,
        conversationID: String,
        prompt: String,
        model: String
    ) async throws -> String {
        let url = URL(string: "https://grok.x.com/2/add-response")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyWebAuth(to: &request, session: webSession)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "conversationId": conversationID,
            "responses": [
                [
                    "message": prompt,
                    "sender": 1
                ]
            ],
            "systemPromptName": model.lowercased().contains("fun") ? "fun" : "",
            "grokModelOptionId": model
        ])

        let (data, response) = try await self.session.data(for: request)
        try Self.validate(response: response, data: data)

        if let text = String(data: data, encoding: .utf8) {
            // Streaming-ish payloads may contain multiple JSON chunks; extract readable text/JSON.
            if let extracted = Self.extractJSONObject(from: text) {
                return extracted
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = object["message"] as? String { return message }
                if let result = object["result"] as? String { return result }
                if let choices = object["choices"] as? [[String: Any]],
                   let content = (choices.first?["message"] as? [String: Any])?["content"] as? String {
                    return content
                }
            }
            return text
        }

        throw XWebSessionError.invalidResponse
    }

    private func applyWebAuth(to request: inout URLRequest, session: XWebSession) {
        request.setValue("Bearer \(Self.publicBearer)", forHTTPHeaderField: "Authorization")
        request.setValue(session.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("Browser", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("https://x.com", forHTTPHeaderField: "Origin")
        request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw XWebSessionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw XWebSessionError.server(statusCode: http.statusCode, message: message)
        }
    }

    private static func parsePayload(from content: String, model: String) throws -> GrokPayload {
        let jsonData: Data
        if let data = content.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            jsonData = data
        } else if let extracted = extractJSONObject(from: content)?.data(using: .utf8) {
            jsonData = extracted
        } else {
            // Fallback: treat whole reply as summary when endpoint returns prose.
            return GrokPayload(
                title: Self.makeTitle(from: content),
                summary: content.trimmingCharacters(in: .whitespacesAndNewlines),
                category: "Inbox",
                tags: ["grok"],
                model: model
            )
        }

        struct EnrichmentJSON: Decodable {
            var title: String?
            var summary: String
            var category: String
            var tags: [String]
        }

        if let object = try? JSONDecoder().decode(EnrichmentJSON.self, from: jsonData) {
            return GrokPayload(
                title: object.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? Self.makeTitle(from: object.summary),
                summary: object.summary,
                category: object.category,
                tags: Array(object.tags.prefix(5)),
                model: model
            )
        }

        return GrokPayload(
            title: Self.makeTitle(from: content),
            summary: content.trimmingCharacters(in: .whitespacesAndNewlines),
            category: "Inbox",
            tags: ["grok"],
            model: model
        )
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private static func makeTitle(from text: String) -> String {
        let line = text.split(whereSeparator: { ".!?。！？\n".contains($0) }).first.map(String.init) ?? text
        return String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }
}

private struct VerifyUser: Decodable {
    var id: Int64
    var name: String
    var screenName: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case screenName = "screen_name"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
