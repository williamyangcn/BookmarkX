import Foundation

/// Fetches bookmarks using the same cookie session as x.com (GraphQL).
/// Official API v2 bookmarks require OAuth; web login cannot use that path.
actor XWebBookmarksClient {
    private let session: URLSession
    private var cachedQueryIDs: [String: String] = [:]
    /// Once an operation works, keep using it for the rest of the process lifetime.
    private var preferredOperationName: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBookmarks(
        webSession: XWebSession,
        count: Int,
        cursor: String?
    ) async throws -> BookmarkPage {
        let clamped = min(max(count, 1), 100)
        let ids = try await resolveQueryIDs(webSession: webSession)

        var candidates = Self.operationCandidates(from: ids)
        if let preferredOperationName {
            candidates.sort { lhs, rhs in
                let l = lhs.name == preferredOperationName ? 0 : 1
                let r = rhs.name == preferredOperationName ? 0 : 1
                return l < r
            }
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                let page = try await fetch(
                    webSession: webSession,
                    operation: candidate,
                    count: clamped,
                    cursor: cursor
                )
                // Empty first page: Bookmarks with no items is a real empty library.
                // Other ops may return empty when stale — try the next candidate.
                if page.tweets.isEmpty, cursor == nil {
                    if candidate.name == "Bookmarks" {
                        preferredOperationName = candidate.name
                        return page
                    }
                    lastError = XWebSessionError.invalidResponse
                    continue
                }
                // Prefer sticking to Bookmarks; Search can hide new items / reorder.
                if candidate.name == "Bookmarks" || preferredOperationName == nil {
                    preferredOperationName = candidate.name
                }
                return page
            } catch {
                lastError = error
            }
        }

        throw lastError ?? XWebSessionError.invalidResponse
    }

    func deleteBookmark(webSession: XWebSession, tweetID: String) async throws {
        let ids = try await resolveQueryIDs(webSession: webSession)
        let queryID = ids["DeleteBookmark"] ?? Self.fallbackDeleteQueryID
        let url = URL(string: "https://x.com/i/api/graphql/\(queryID)/DeleteBookmark")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyWebAuth(to: &request, session: webSession)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "variables": ["tweet_id": tweetID],
            "queryId": queryID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    // MARK: - Fetch

    private struct GraphQLOperation {
        var queryID: String
        var name: String
        var variables: [String: Any]
        var features: [String: Bool]
    }

    private func fetch(
        webSession: XWebSession,
        operation: GraphQLOperation,
        count: Int,
        cursor: String?
    ) async throws -> BookmarkPage {
        var variables = operation.variables
        variables["count"] = count
        if let cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }

        let variablesJSON = try Self.jsonString(variables)
        let featuresJSON = try Self.jsonString(operation.features)
        var components = URLComponents(
            string: "https://x.com/i/api/graphql/\(operation.queryID)/\(operation.name)"
        )!
        components.queryItems = [
            URLQueryItem(name: "variables", value: variablesJSON),
            URLQueryItem(name: "features", value: featuresJSON)
        ]
        guard let url = components.url else {
            throw XWebSessionError.invalidResponse
        }

        var request = URLRequest(url: url)
        applyWebAuth(to: &request, session: webSession)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let tweets = try Self.parseTweets(from: data)
        let next = Self.parseBottomCursor(from: data)
        return BookmarkPage(tweets: tweets, nextToken: next, resultCount: tweets.count)
    }

    private static func operationCandidates(from ids: [String: String]) -> [GraphQLOperation] {
        var result: [GraphQLOperation] = []

        // Prefer the real Bookmarks timeline (newest-first). Search timeline can
        // succeed with incomplete / differently ordered results and hide new bookmarks.
        if let id = ids["Bookmarks"] {
            result.append(
                GraphQLOperation(
                    queryID: id,
                    name: "Bookmarks",
                    variables: [
                        "count": 20,
                        "includePromotedContent": false
                    ],
                    features: commonFeatures.merging([
                        "graphql_timeline_v2_bookmark_timeline": true
                    ]) { _, new in new }
                )
            )
        }

        let searchID = ids["BookmarkSearchTimeline"] ?? fallbackSearchQueryID
        result.append(
            GraphQLOperation(
                queryID: searchID,
                name: "BookmarkSearchTimeline",
                variables: [
                    "rawQuery": "",
                    "count": 20,
                    "querySource": ""
                ],
                features: commonFeatures
            )
        )

        for (id, name) in fallbackBookmarks {
            if result.contains(where: { $0.queryID == id && $0.name == name }) { continue }
            result.append(
                GraphQLOperation(
                    queryID: id,
                    name: name,
                    variables: name == "BookmarkSearchTimeline"
                        ? ["rawQuery": "", "count": 20, "querySource": ""]
                        : ["count": 20, "includePromotedContent": false],
                    features: commonFeatures.merging(
                        name == "Bookmarks" ? ["graphql_timeline_v2_bookmark_timeline": true] : [:]
                    ) { _, new in new }
                )
            )
        }

        // Bookmarks before search in fallbacks too.
        result.sort { lhs, rhs in
            let l = lhs.name == "Bookmarks" ? 0 : 1
            let r = rhs.name == "Bookmarks" ? 0 : 1
            return l < r
        }

        return result
    }

    // MARK: - Query ID discovery

    private func resolveQueryIDs(webSession: XWebSession) async throws -> [String: String] {
        if cachedQueryIDs["Bookmarks"] != nil || cachedQueryIDs["BookmarkSearchTimeline"] != nil {
            return cachedQueryIDs
        }
        if let disk = loadCachedQueryIDs(), !disk.isEmpty {
            cachedQueryIDs = disk
            return disk
        }

        // Start sync immediately with known fallbacks — JS discovery can take minutes.
        var fallback: [String: String] = [:]
        for item in Self.fallbackBookmarks where fallback[item.name] == nil {
            fallback[item.name] = item.id
        }
        fallback["DeleteBookmark"] = Self.fallbackDeleteQueryID
        cachedQueryIDs = fallback

        Task { [webSession] in
            let discovered = await self.discoverQueryIDs(webSession: webSession)
            guard !discovered.isEmpty else { return }
            var merged = fallback
            for (key, value) in discovered {
                merged[key] = value
            }
            self.cachedQueryIDs = merged
            self.saveCachedQueryIDs(merged)
        }

        return fallback
    }

    private func discoverQueryIDs(webSession: XWebSession) async -> [String: String] {
        var found: [String: String] = [:]
        let seedURLs = [
            URL(string: "https://x.com/i/bookmarks")!,
            URL(string: "https://x.com/")!
        ]

        var scriptURLs: [URL] = []
        for seed in seedURLs {
            guard let html = try? await fetchString(url: seed, webSession: webSession) else { continue }
            scriptURLs.append(contentsOf: Self.extractScriptURLs(from: html))
        }

        // Prefer client-web bundles that usually carry GraphQL metadata.
        let prioritized = scriptURLs
            .filter { $0.absoluteString.contains("client-web") || $0.absoluteString.contains("main.") }
            .prefix(25)

        for scriptURL in prioritized {
            guard let js = try? await fetchString(url: scriptURL, webSession: webSession) else { continue }
            let pairs = Self.extractQueryIDs(from: js)
            for (name, id) in pairs where name == "Bookmarks"
                || name == "BookmarkSearchTimeline"
                || name == "DeleteBookmark" {
                found[name] = id
            }
            if found["Bookmarks"] != nil || found["BookmarkSearchTimeline"] != nil {
                break
            }
        }
        return found
    }

    private func fetchString(url: URL, webSession: XWebSession) async throws -> String {
        var request = URLRequest(url: url)
        applyWebAuth(to: &request, session: webSession)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func extractScriptURLs(from html: String) -> [URL] {
        let pattern = #"https://abs\.twimg\.com/responsive-web/client-web[^"']+\.js"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range, in: html) else { return nil }
            return URL(string: String(html[r]))
        }
    }

    private static func extractQueryIDs(from js: String) -> [String: String] {
        // queryId:"ID",operationName:"Name"  (order may swap)
        let patterns = [
            #"queryId:"([A-Za-z0-9_-]+)",operationName:"([A-Za-z0-9_]+)""#,
            #"operationName:"([A-Za-z0-9_]+)",[^}]{0,80}queryId:"([A-Za-z0-9_-]+)""#
        ]
        var result: [String: String] = [:]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(js.startIndex..<js.endIndex, in: js)
            for match in regex.matches(in: js, range: range) {
                guard match.numberOfRanges == 3,
                      let r1 = Range(match.range(at: 1), in: js),
                      let r2 = Range(match.range(at: 2), in: js) else { continue }
                if index == 0 {
                    result[String(js[r2])] = String(js[r1])
                } else {
                    result[String(js[r1])] = String(js[r2])
                }
            }
        }
        return result
    }

    private func queryIDCacheURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let folder = dir.appendingPathComponent("BookmarkX", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("graphql-query-ids.json")
    }

    private func loadCachedQueryIDs() -> [String: String]? {
        guard let url = queryIDCacheURL(),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return object
    }

    private func saveCachedQueryIDs(_ ids: [String: String]) {
        guard let url = queryIDCacheURL(),
              let data = try? JSONSerialization.data(withJSONObject: ids) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Parsing

    private static func parseTweets(from data: Data) throws -> [RemoteBookmarkTweet] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XWebSessionError.invalidResponse
        }
        if let errors = root["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String {
            throw XWebSessionError.server(statusCode: 400, message: message)
        }

        // Timeline entry order is newest-first. A raw recursive walk shuffles that
        // order (and pulls quoted/retweeted tweets), which breaks incremental sync.
        let ordered = parseOrderedTimelineTweets(from: root)
        if !ordered.isEmpty {
            return ordered
        }

        // Last-resort fallback for unexpected payloads.
        var tweets: [RemoteBookmarkTweet] = []
        var seen = Set<String>()
        walk(root) { object in
            guard let tweet = parseTweetObject(object), seen.insert(tweet.id).inserted else { return }
            tweets.append(tweet)
        }
        return tweets
    }

    /// Prefer `instructions → entries` order so catch-up sees newest bookmarks first.
    private static func parseOrderedTimelineTweets(from root: [String: Any]) -> [RemoteBookmarkTweet] {
        var tweets: [RemoteBookmarkTweet] = []
        var seen = Set<String>()

        walk(root) { object in
            guard let instructions = object["instructions"] as? [[String: Any]] else { return }
            for instruction in instructions {
                guard let entries = instruction["entries"] as? [Any] else { continue }
                for case let entry as [String: Any] in entries {
                    guard let tweet = tweetFromTimelineEntry(entry),
                          seen.insert(tweet.id).inserted else { continue }
                    tweets.append(tweet)
                }
            }
        }

        return tweets
    }

    private static func tweetFromTimelineEntry(_ entry: [String: Any]) -> RemoteBookmarkTweet? {
        let entryID = (entry["entryId"] as? String) ?? ""
        if entryID.hasPrefix("cursor-") {
            return nil
        }

        if let content = entry["content"] as? [String: Any] {
            let itemContent = (content["itemContent"] as? [String: Any]) ?? content
            if let tweetResults = (itemContent["tweet_results"] as? [String: Any])
                ?? (itemContent["tweetResult"] as? [String: Any]),
               let result = tweetResults["result"] as? [String: Any],
               let tweet = parseTweetObject(result) {
                return tweet
            }
        }

        // Stay inside this entry so quoted/retweeted nested tweets aren't collected
        // as separate bookmark rows out of order.
        var found: RemoteBookmarkTweet?
        walk(entry) { object in
            guard found == nil else { return }
            found = parseTweetObject(object)
        }
        return found
    }

    private static func parseBottomCursor(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return nil
        }
        var cursor: String?
        walk(root) { object in
            let type = (object["cursorType"] as? String)
                ?? (object["content"] as? [String: Any])?["cursorType"] as? String
            if type == "Bottom" || type == "BottomCursor" {
                if let value = object["value"] as? String {
                    cursor = value
                } else if let value = (object["content"] as? [String: Any])?["value"] as? String {
                    cursor = value
                }
            }
            if let entryID = object["entryId"] as? String,
               entryID.hasPrefix("cursor-bottom"),
               let content = object["content"] as? [String: Any],
               let value = content["value"] as? String {
                cursor = value
            }
        }
        return cursor
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let object = node as? [String: Any] {
            visit(object)
            for value in object.values {
                walk(value, visit: visit)
            }
        } else if let array = node as? [Any] {
            for value in array {
                walk(value, visit: visit)
            }
        }
    }

    private static func parseTweetObject(_ object: [String: Any]) -> RemoteBookmarkTweet? {
        // Typical shapes: Tweet / TweetWithVisibilityResults
        let result: [String: Any]
        if let typename = object["__typename"] as? String {
            if typename == "Tweet" {
                result = object
            } else if typename == "TweetWithVisibilityResults",
                      let nested = object["tweet"] as? [String: Any] {
                result = nested
            } else {
                return nil
            }
        } else if object["legacy"] != nil, object["rest_id"] != nil {
            result = object
        } else {
            return nil
        }

        guard
            let id = (result["rest_id"] as? String)
                ?? (result["legacy"] as? [String: Any])?["id_str"] as? String,
            let legacy = result["legacy"] as? [String: Any],
            isValidTweetID(id)
        else { return nil }

        let text = (legacy["full_text"] as? String)
            ?? ((result["note_tweet"] as? [String: Any])?["note_tweet_results"] as? [String: Any])
            .flatMap { ($0["result"] as? [String: Any])?["text"] as? String }
            ?? ""

        let userResult = ((result["core"] as? [String: Any])?["user_results"] as? [String: Any])?["result"] as? [String: Any]
        let userLegacy = userResult?["legacy"] as? [String: Any]
        guard
            let authorID = (userResult?["rest_id"] as? String)
                ?? (legacy["user_id_str"] as? String),
            isValidTweetID(authorID),
            let username = userLegacy?["screen_name"] as? String,
            !username.isEmpty,
            username != "unknown"
        else { return nil }

        let name = (userLegacy?["name"] as? String) ?? username
        let avatar = userLegacy?["profile_image_url_https"] as? String

        let createdAt = parseTwitterDate(legacy["created_at"] as? String) ?? Date()
        let metrics = legacy["favorite_count"] as? Int

        return RemoteBookmarkTweet(
            id: id,
            text: text,
            authorID: authorID,
            authorUsername: username,
            authorName: name,
            authorProfileImageURL: avatar,
            createdAt: createdAt,
            lang: legacy["lang"] as? String,
            likeCount: metrics ?? 0,
            retweetCount: (legacy["retweet_count"] as? Int) ?? 0,
            replyCount: (legacy["reply_count"] as? Int) ?? 0,
            quoteCount: (legacy["quote_count"] as? Int) ?? 0,
            conversationID: legacy["conversation_id_str"] as? String,
            media: [],
            rawJSON: nil
        )
    }

    /// Snowflake IDs are digits only. Reject t.co / URL false positives from GraphQL walks.
    private static func isValidTweetID(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    private static func parseTwitterDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter.date(from: value)
    }

    // MARK: - Auth / helpers

    private func applyWebAuth(to request: inout URLRequest, session: XWebSession) {
        request.setValue("Bearer \(XWebSessionClient.publicBearer)", forHTTPHeaderField: "Authorization")
        request.setValue(session.ct0, forHTTPHeaderField: "x-csrf-token")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("Browser", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("https://x.com", forHTTPHeaderField: "Origin")
        request.setValue("https://x.com/i/bookmarks", forHTTPHeaderField: "Referer")
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
            throw XWebSessionError.server(statusCode: http.statusCode, message: String(message.prefix(300)))
        }
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw XWebSessionError.invalidResponse
        }
        return string
    }

    private static let fallbackSearchQueryID = "fHKoSa-2dbV1UbhUy3EvcA"
    private static let fallbackDeleteQueryID = "Wlmlj2-xzySOfYNBodNipg"
    private static let fallbackBookmarks: [(id: String, name: String)] = [
        ("tmd4ifV8RHltzn8ymGg1aw", "Bookmarks"),
        ("-LGfdImKeQz0xS_jjUwzlA", "Bookmarks"),
        ("fHKoSa-2dbV1UbhUy3EvcA", "BookmarkSearchTimeline")
    ]

    private static let commonFeatures: [String: Bool] = [
        "rweb_tipjar_consumption_enabled": true,
        "responsive_web_graphql_exclude_directive_enabled": true,
        "verified_phone_label_enabled": false,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "tweet_awards_web_tipping_enabled": false,
        "creator_subscriptions_quote_tweet_preview_enabled": false,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "rweb_video_timestamps_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": true,
        "responsive_web_enhance_cards_enabled": false
    ]
}
