import Foundation

actor XAPIClient {
    enum Auth: Sendable {
        case oauth(accessToken: String, userID: String, refreshToken: String?, username: String?)
        case webSession(XWebSession, userID: String)
    }

    private var auth: Auth?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.x.com/2")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func configure(with auth: Auth) {
        self.auth = auth
    }

    func isConfigured() -> Bool {
        auth != nil
    }

    /// Fetches bookmarks newest-first.
    func fetchBookmarks(
        maxResults: Int = 100,
        paginationToken: String? = nil
    ) async throws -> BookmarkPage {
        let auth = try requireAuth()
        let clamped = min(max(maxResults, 1), 100)
        let userID = auth.userID

        var components = URLComponents(
            url: baseURL.appending(path: "users/\(userID)/bookmarks"),
            resolvingAgainstBaseURL: false
        )
        var items: [URLQueryItem] = [
            URLQueryItem(name: "max_results", value: String(clamped)),
            URLQueryItem(
                name: "tweet.fields",
                value: "created_at,lang,public_metrics,conversation_id,attachments,entities"
            ),
            URLQueryItem(name: "expansions", value: "author_id,attachments.media_keys"),
            URLQueryItem(
                name: "user.fields",
                value: "name,username,profile_image_url"
            ),
            URLQueryItem(
                name: "media.fields",
                value: "type,url,preview_image_url,width,height"
            )
        ]
        if let paginationToken, !paginationToken.isEmpty {
            items.append(URLQueryItem(name: "pagination_token", value: paginationToken))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw XAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        applyAuth(auth, to: &request)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(BookmarksAPIResponse.self, from: data)
        return BookmarkPage(
            tweets: decoded.resolvedTweets(),
            nextToken: decoded.meta?.nextToken,
            resultCount: decoded.meta?.resultCount ?? decoded.data?.count ?? 0
        )
    }

    func deleteBookmark(tweetID: String) async throws {
        let auth = try requireAuth()
        let url = baseURL.appending(path: "users/\(auth.userID)/bookmarks/\(tweetID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuth(auth, to: &request)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    private func requireAuth() throws -> Auth {
        guard let auth else {
            throw XAPIError.notConfigured
        }
        return auth
    }

    private func applyAuth(_ auth: Auth, to request: inout URLRequest) {
        switch auth {
        case .oauth(let accessToken, _, _, _):
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        case .webSession(let webSession, _):
            request.setValue("Bearer \(XWebSessionClient.publicBearer)", forHTTPHeaderField: "Authorization")
            request.setValue(webSession.ct0, forHTTPHeaderField: "x-csrf-token")
            request.setValue(webSession.cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
            request.setValue("Browser", forHTTPHeaderField: "x-twitter-active-user")
            request.setValue("https://x.com", forHTTPHeaderField: "Origin")
            request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw XAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(XAPIErrorBody.self, from: data)).flatMap {
                $0.detail ?? $0.title ?? $0.errors?.first?.message
            } ?? (String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
            throw XAPIError.server(statusCode: http.statusCode, message: message)
        }
    }
}

private extension XAPIClient.Auth {
    var userID: String {
        switch self {
        case .oauth(_, let userID, _, _): userID
        case .webSession(_, let userID): userID
        }
    }
}

struct BookmarkPage: Sendable {
    var tweets: [RemoteBookmarkTweet]
    var nextToken: String?
    var resultCount: Int
}

struct RemoteBookmarkTweet: Sendable, Equatable {
    var id: String
    var text: String
    var authorID: String
    var authorUsername: String
    var authorName: String
    var authorProfileImageURL: String?
    var createdAt: Date
    var lang: String?
    var likeCount: Int
    var retweetCount: Int
    var replyCount: Int
    var quoteCount: Int
    var conversationID: String?
    var media: [RemoteMedia]
    var rawJSON: String?
}

struct RemoteMedia: Sendable, Equatable {
    var id: String
    var type: String
    var url: String?
    var previewImageURL: String?
    var width: Int?
    var height: Int?
}

enum XAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "sync.error.notConfigured")
        case .invalidURL:
            String(localized: "sync.error.invalidURL")
        case .invalidResponse:
            String(localized: "sync.error.invalidResponse")
        case .server(let statusCode, let message):
            "X API \(statusCode): \(message)"
        }
    }
}

// MARK: - Decoding

private struct BookmarksAPIResponse: Decodable {
    var data: [APITweet]?
    var includes: Includes?
    var meta: Meta?

    struct Meta: Decodable {
        var resultCount: Int?
        var nextToken: String?

        enum CodingKeys: String, CodingKey {
            case resultCount = "result_count"
            case nextToken = "next_token"
        }
    }

    struct Includes: Decodable {
        var users: [APIUser]?
        var media: [APIMedia]?
    }

    struct APITweet: Decodable {
        var id: String
        var text: String
        var authorID: String?
        var createdAt: String?
        var lang: String?
        var conversationID: String?
        var publicMetrics: PublicMetrics?
        var attachments: Attachments?

        enum CodingKeys: String, CodingKey {
            case id, text, lang
            case authorID = "author_id"
            case createdAt = "created_at"
            case conversationID = "conversation_id"
            case publicMetrics = "public_metrics"
            case attachments
        }
    }

    struct PublicMetrics: Decodable {
        var likeCount: Int?
        var retweetCount: Int?
        var replyCount: Int?
        var quoteCount: Int?

        enum CodingKeys: String, CodingKey {
            case likeCount = "like_count"
            case retweetCount = "retweet_count"
            case replyCount = "reply_count"
            case quoteCount = "quote_count"
        }
    }

    struct Attachments: Decodable {
        var mediaKeys: [String]?

        enum CodingKeys: String, CodingKey {
            case mediaKeys = "media_keys"
        }
    }

    struct APIUser: Decodable {
        var id: String
        var name: String
        var username: String
        var profileImageURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name, username
            case profileImageURL = "profile_image_url"
        }
    }

    struct APIMedia: Decodable {
        var mediaKey: String
        var type: String
        var url: String?
        var previewImageURL: String?
        var width: Int?
        var height: Int?

        enum CodingKeys: String, CodingKey {
            case type, url, width, height
            case mediaKey = "media_key"
            case previewImageURL = "preview_image_url"
        }
    }

    func resolvedTweets() -> [RemoteBookmarkTweet] {
        let users = Dictionary(uniqueKeysWithValues: (includes?.users ?? []).map { ($0.id, $0) })
        let mediaByKey = Dictionary(uniqueKeysWithValues: (includes?.media ?? []).map { ($0.mediaKey, $0) })

        return (data ?? []).compactMap { tweet in
            guard let authorID = tweet.authorID else { return nil }
            let user = users[authorID]
            let mediaKeys = tweet.attachments?.mediaKeys ?? []
            let media: [RemoteMedia] = mediaKeys.compactMap { key in
                guard let item = mediaByKey[key] else { return nil }
                return RemoteMedia(
                    id: item.mediaKey,
                    type: item.type,
                    url: item.url,
                    previewImageURL: item.previewImageURL,
                    width: item.width,
                    height: item.height
                )
            }

            let createdAt = Self.parseDate(tweet.createdAt) ?? Date()
            let rawJSON = try? String(
                data: JSONEncoder().encode(RawTweetEnvelope(id: tweet.id, text: tweet.text)),
                encoding: .utf8
            )

            return RemoteBookmarkTweet(
                id: tweet.id,
                text: tweet.text,
                authorID: authorID,
                authorUsername: user?.username ?? "unknown",
                authorName: user?.name ?? "Unknown",
                authorProfileImageURL: user?.profileImageURL,
                createdAt: createdAt,
                lang: tweet.lang,
                likeCount: tweet.publicMetrics?.likeCount ?? 0,
                retweetCount: tweet.publicMetrics?.retweetCount ?? 0,
                replyCount: tweet.publicMetrics?.replyCount ?? 0,
                quoteCount: tweet.publicMetrics?.quoteCount ?? 0,
                conversationID: tweet.conversationID,
                media: media,
                rawJSON: rawJSON
            )
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}

private struct RawTweetEnvelope: Encodable {
    var id: String
    var text: String
}

private struct XAPIErrorBody: Decodable {
    struct Item: Decodable {
        var message: String?
    }

    var title: String?
    var detail: String?
    var errors: [Item]?
}
