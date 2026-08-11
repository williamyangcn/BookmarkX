import Foundation

struct GrokPayload: Sendable {
    var title: String
    var summary: String
    var category: String
    var tags: [String]
    var model: String?
}

/// Official xAI API (OpenAI-compatible chat completions).
struct XAIAPITransport: Sendable {
    var apiKey: String
    var model: String
    var outputLanguage: AppLanguage
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.x.ai/v1")!

    func enrich(
        tweetText: String,
        authorUsername: String?,
        existingFolders: [String] = []
    ) async throws -> GrokPayload {
        let url = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let languageInstruction: String = switch outputLanguage {
        case .english: "Respond in English."
        case .simplifiedChinese: "用简体中文回答。"
        case .system: "Match the language of the tweet when possible; otherwise use Simplified Chinese."
        }

        let folderHint: String
        if existingFolders.isEmpty {
            folderHint = """
            Invent a short reusable category (2-8 chars in Chinese, or 1-3 English words).
            Prefer specific topics over generic labels like Inbox/Misc/Other.
            """
        } else {
            let listed = existingFolders.prefix(40).joined(separator: ", ")
            folderHint = """
            Prefer an existing folder when it fits: \(listed).
            If none fit well, invent a NEW short reusable category so folders can grow with content.
            Do not force everything into a catch-all like 待读 / Inbox.
            """
        }

        let authorLine = authorUsername.map { "Author: @\($0)\n" } ?? ""
        let userPrompt = """
        \(authorLine)Tweet:
        \(tweetText)

        Return JSON only with keys:
        - title: a concise descriptive title, no more than 20 words
        - summary: one or two concise sentences
        - category: a short topic folder label
        - tags: 1 to 5 short tags
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You organize X/Twitter bookmarks into a personal knowledge base.
                    \(languageInstruction)
                    Keep category and tags short and reusable.
                    \(folderHint)
                    """
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw GrokError.emptyContent
        }

        return try Self.parsePayload(from: content, model: decoded.model ?? model)
    }

    private static func parsePayload(from content: String, model: String) throws -> GrokPayload {
        let jsonData: Data
        if let data = content.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            jsonData = data
        } else if let extracted = extractJSONObject(from: content)?.data(using: .utf8) {
            jsonData = extracted
        } else {
            throw GrokError.decodingFailed
        }

        let object = try JSONDecoder().decode(EnrichmentJSON.self, from: jsonData)
        let tags = object.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !object.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !object.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrokError.decodingFailed
        }

        return GrokPayload(
            title: object.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? makeTitle(from: object.summary),
            summary: object.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            category: object.category.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: Array(tags.prefix(5)),
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

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)).flatMap {
                $0.error?.message ?? $0.message
            } ?? (String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
            throw GrokError.server(statusCode: http.statusCode, message: message)
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }

    var model: String?
    var choices: [Choice]
}

private struct EnrichmentJSON: Decodable {
    var title: String?
    var summary: String
    var category: String
    var tags: [String]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct APIErrorEnvelope: Decodable {
    struct NestedError: Decodable {
        var message: String?
    }

    var error: NestedError?
    var message: String?
}
