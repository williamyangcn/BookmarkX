import Foundation
import Observation

struct BookmarkSyncOptions: Sendable, Equatable {
    /// Max *new* bookmarks to import per sync run (1...100). Default 100.
    var batchSize: Int = 100
    /// X Bookmarks API returns newest first; kept explicit for settings UI.
    var newestFirst: Bool = true
    /// Skip bookmarks already stored locally, then keep paging for older unfetched ones.
    var skipAlreadySynced: Bool = true
    /// After a bookmark is saved locally, delete it from X.
    var deleteFromXAfterSync: Bool = false
}

struct BookmarkSyncResult: Sendable, Equatable {
    var fetched: Int = 0
    var imported: Int = 0
    var skipped: Int = 0
    var updated: Int = 0
    var restored: Int = 0
    var deletedFromX: Int = 0
    var failedDeletes: Int = 0
}

enum BookmarkSyncPhase: Equatable, Sendable {
    case idle
    case preparing
    case fetching
    case importing
    case deletingRemote
    case completed(BookmarkSyncResult)
    case failed(String)
}

/// Progress toward the per-refresh batch target.
enum BookmarkSyncMath {
    /// Counts bookmarks that satisfy the current sync goal.
    /// With skip-already-synced on: only brand-new / restored rows count (skipped do not).
    static func batchProgress(_ result: BookmarkSyncResult, skipAlreadySynced: Bool) -> Int {
        let gained = result.imported + result.restored
        if skipAlreadySynced {
            return gained
        }
        return gained + result.updated
    }
}

private enum SyncTransport {
    case oauth(XAPIClient)
    case web(XWebBookmarksClient, XWebSession)
}

@Observable
@MainActor
final class BookmarkSyncService {
    private let database: AppDatabase
    private let apiClient: XAPIClient
    private let webBookmarksClient: XWebBookmarksClient

    private(set) var phase: BookmarkSyncPhase = .idle
    private(set) var lastResult: BookmarkSyncResult?
    private var isRunning = false
    private var transport: SyncTransport?

    /// Safety cap while scanning past already-synced pages (100/page → up to 10k).
    private let maxPagesPerSync = 100

    init(
        database: AppDatabase,
        apiClient: XAPIClient = XAPIClient(),
        webBookmarksClient: XWebBookmarksClient = XWebBookmarksClient()
    ) {
        self.database = database
        self.apiClient = apiClient
        self.webBookmarksClient = webBookmarksClient
    }

    func configureAPI() async throws {
        let store = KeychainStore.shared

        if
            let accessToken = try store.load(.xAccessToken), !accessToken.isEmpty,
            let userID = try store.load(.xUserID), !userID.isEmpty
        {
            await apiClient.configure(
                with: .oauth(
                    accessToken: accessToken,
                    userID: userID,
                    refreshToken: try? store.load(.xRefreshToken),
                    username: try? store.load(.xUsername)
                )
            )
            transport = .oauth(apiClient)
            return
        }

        guard var webSession = try XWebSessionStore.load() else {
            throw XAPIError.notConfigured
        }

        if webSession.userID?.isEmpty != false {
            if let verified = try? await XWebSessionClient().verify(session: webSession) {
                webSession = verified
                try XWebSessionStore.save(webSession)
            }
        }

        // Web login sync uses GraphQL (cookie session). OAuth v2 bookmarks need Developer tokens.
        transport = .web(webBookmarksClient, webSession)
    }

    func sync(options: BookmarkSyncOptions) async throws -> BookmarkSyncResult {
        guard !isRunning else {
            throw BookmarkSyncError.alreadyRunning
        }

        isRunning = true
        phase = .preparing

        do {
            try await configureAPI()
            guard let transport else { throw XAPIError.notConfigured }

            var result = BookmarkSyncResult()
            var paginationToken: String?
            let target = min(max(options.batchSize, 1), 100)
            var pages = 0

            // Keep paging through X bookmarks until we import `target` *unfetched*
            // ones (or run out). Already-synced rows are skipped and do NOT fill the quota.
            while BookmarkSyncMath.batchProgress(result, skipAlreadySynced: options.skipAlreadySynced) < target {
                pages += 1
                if pages > maxPagesPerSync {
                    break
                }

                phase = .fetching
                let page = try await fetchPage(
                    transport: transport,
                    maxResults: 100,
                    paginationToken: paginationToken
                )

                if page.tweets.isEmpty {
                    break
                }

                result.fetched += page.tweets.count
                phase = .importing

                for tweet in page.tweets {
                    if BookmarkSyncMath.batchProgress(
                        result,
                        skipAlreadySynced: options.skipAlreadySynced
                    ) >= target {
                        break
                    }

                    let exists = try await database.dbWriter.read { db in
                        try BookmarkQueries.bookmarkExists(db: db, tweetID: tweet.id)
                    }

                    if exists, options.skipAlreadySynced {
                        result.skipped += 1
                        continue
                    }

                    let outcome = try await database.dbWriter.write { db in
                        try BookmarkQueries.upsertRemoteBookmark(db: db, tweet: tweet)
                    }

                    switch outcome {
                    case .inserted:
                        result.imported += 1
                    case .updated:
                        result.updated += 1
                    case .restored:
                        result.restored += 1
                    case .unchanged:
                        result.skipped += 1
                    }

                    let shouldDelete = options.deleteFromXAfterSync
                        && (outcome == .inserted || outcome == .restored
                            || (!options.skipAlreadySynced && outcome == .updated))

                    if shouldDelete {
                        phase = .deletingRemote
                        do {
                            try await deleteRemote(transport: transport, tweetID: tweet.id)
                            result.deletedFromX += 1
                        } catch {
                            result.failedDeletes += 1
                        }
                    }
                }

                if BookmarkSyncMath.batchProgress(
                    result,
                    skipAlreadySynced: options.skipAlreadySynced
                ) >= target {
                    break
                }

                guard let next = page.nextToken, !next.isEmpty else {
                    break
                }
                // Cursor did not advance — stop to avoid a tight loop.
                if next == paginationToken {
                    break
                }
                paginationToken = next
            }

            lastResult = result
            phase = .completed(result)
            isRunning = false
            return result
        } catch {
            phase = .failed(error.localizedDescription)
            isRunning = false
            throw error
        }
    }

    func deleteRemoteBookmark(tweetID: String) async throws {
        try await configureAPI()
        guard let transport else { throw XAPIError.notConfigured }
        try await deleteRemote(transport: transport, tweetID: tweetID)
    }

    private func fetchPage(
        transport: SyncTransport,
        maxResults: Int,
        paginationToken: String?
    ) async throws -> BookmarkPage {
        switch transport {
        case .oauth(let client):
            return try await client.fetchBookmarks(
                maxResults: maxResults,
                paginationToken: paginationToken
            )
        case .web(let client, let webSession):
            return try await client.fetchBookmarks(
                webSession: webSession,
                count: maxResults,
                cursor: paginationToken
            )
        }
    }

    private func deleteRemote(transport: SyncTransport, tweetID: String) async throws {
        switch transport {
        case .oauth(let client):
            try await client.deleteBookmark(tweetID: tweetID)
        case .web(let client, let webSession):
            try await client.deleteBookmark(webSession: webSession, tweetID: tweetID)
        }
    }
}

enum BookmarkSyncError: LocalizedError {
    case alreadyRunning

    var errorDescription: String? {
        AppLocalization.text("sync.error.alreadyRunning")
    }
}
