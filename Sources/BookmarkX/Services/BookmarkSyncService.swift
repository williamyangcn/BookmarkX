import Foundation
import Observation

struct BookmarkSyncOptions: Sendable, Equatable {
    /// Max *new* bookmarks to import per sync run (1...100). Default 100.
    var batchSize: Int = 100
    /// X Bookmarks API returns newest first; kept explicit for settings UI.
    var newestFirst: Bool = true
    /// Skip bookmarks already stored locally.
    var skipAlreadySynced: Bool = true
    /// After a bookmark is saved locally, delete it from X.
    var deleteFromXAfterSync: Bool = false
    /// True once a prior sync walked to the end of the remote list.
    var backfillComplete: Bool = false
    /// Pagination cursor for resuming older bookmark backfill after catch-up.
    var backfillCursor: String? = nil
}

struct BookmarkSyncResult: Sendable, Equatable {
    var fetched: Int = 0
    var imported: Int = 0
    var skipped: Int = 0
    var updated: Int = 0
    var restored: Int = 0
    var deletedFromX: Int = 0
    var failedDeletes: Int = 0
    /// Cursor to resume older backfill; nil when finished or unused this run.
    var newBackfillCursor: String? = nil
    /// Remote list exhausted.
    var reachedEndOfRemoteList: Bool = false
    /// Catch-up stopped after a streak of already-local bookmarks.
    var stoppedAtKnownFrontier: Bool = false
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

enum BookmarkSyncMath {
    static func batchProgress(_ result: BookmarkSyncResult, skipAlreadySynced: Bool) -> Int {
        let gained = result.imported + result.restored
        if skipAlreadySynced {
            return gained
        }
        return gained + result.updated
    }

    /// Newest-first catch-up: after this many already-local hits in a row, older pages
    /// won't contain brand-new bookmarks.
    static let catchUpSkipStreak = 15

    static func shouldStopCatchUp(
        skipAlreadySynced: Bool,
        consecutiveSkips: Int,
        threshold: Int = catchUpSkipStreak
    ) -> Bool {
        skipAlreadySynced && consecutiveSkips >= threshold
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
            let target = min(max(options.batchSize, 1), 100)
            var pages = 0

            // Phase 1: newest → older until a streak of already-local items (catch-up).
            let catchUp = try await runSyncPass(
                transport: transport,
                options: options,
                result: &result,
                target: target,
                pages: &pages,
                startCursor: nil,
                stopAfterSkipStreak: options.skipAlreadySynced
            )

            let needsBackfill = options.skipAlreadySynced
                && !options.backfillComplete
                && !catchUp.reachedRemoteEnd
                && BookmarkSyncMath.batchProgress(result, skipAlreadySynced: true) < target

            if needsBackfill {
                let resume = options.backfillCursor ?? catchUp.nextCursor
                if let resume, !resume.isEmpty {
                    result.stoppedAtKnownFrontier = false
                    let backfill = try await runSyncPass(
                        transport: transport,
                        options: options,
                        result: &result,
                        target: target,
                        pages: &pages,
                        startCursor: resume,
                        stopAfterSkipStreak: false
                    )
                    result.reachedEndOfRemoteList = backfill.reachedRemoteEnd
                    result.newBackfillCursor = backfill.reachedRemoteEnd ? nil : backfill.nextCursor
                } else {
                    result.reachedEndOfRemoteList = catchUp.reachedRemoteEnd
                    result.newBackfillCursor = catchUp.nextCursor
                }
            } else {
                result.reachedEndOfRemoteList = catchUp.reachedRemoteEnd || options.backfillComplete
                if result.reachedEndOfRemoteList {
                    result.newBackfillCursor = nil
                } else if catchUp.stoppedAtSkipStreak {
                    // Keep prior backfill cursor; catch-up alone doesn't advance it.
                    result.newBackfillCursor = options.backfillCursor ?? catchUp.nextCursor
                } else {
                    result.newBackfillCursor = options.backfillCursor ?? catchUp.nextCursor
                }
            }

            if result.reachedEndOfRemoteList {
                result.newBackfillCursor = nil
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

    private struct SyncPassOutcome {
        var nextCursor: String?
        var reachedRemoteEnd: Bool = false
        var stoppedAtSkipStreak: Bool = false
    }

    private struct PageProcessResult {
        var outcomes: [(tweet: RemoteBookmarkTweet, outcome: BookmarkUpsertOutcome)]
        var skipped: Int
        var consecutiveSkips: Int
        var hitSkipStreak: Bool
    }

    private func runSyncPass(
        transport: SyncTransport,
        options: BookmarkSyncOptions,
        result: inout BookmarkSyncResult,
        target: Int,
        pages: inout Int,
        startCursor: String?,
        stopAfterSkipStreak: Bool
    ) async throws -> SyncPassOutcome {
        var paginationToken = startCursor
        var outcome = SyncPassOutcome()
        var consecutiveSkips = 0

        pageLoop: while BookmarkSyncMath.batchProgress(result, skipAlreadySynced: options.skipAlreadySynced) < target {
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
                outcome.reachedRemoteEnd = true
                outcome.nextCursor = nil
                break
            }

            result.fetched += page.tweets.count
            phase = .importing

            let pageIDs = page.tweets.map(\.id)
            let existingIDs = try await database.dbWriter.read { db in
                try BookmarkQueries.existingBookmarkIDs(db: db, tweetIDs: pageIDs)
            }

            let baselineImported = result.imported
            let baselineRestored = result.restored
            let baselineUpdated = result.updated
            let baselineSkipped = result.skipped
            let streakAtPageStart = consecutiveSkips

            let pageResult: PageProcessResult = try await database.dbWriter.write { db in
                var pageOutcomes: [(tweet: RemoteBookmarkTweet, outcome: BookmarkUpsertOutcome)] = []
                var hitSkipStreak = false
                var pageImported = 0
                var pageRestored = 0
                var pageUpdated = 0
                var pageSkipped = 0
                var localStreak = streakAtPageStart

                for tweet in page.tweets {
                    let progress = BookmarkSyncMath.batchProgress(
                        imported: baselineImported + pageImported,
                        restored: baselineRestored + pageRestored,
                        updated: baselineUpdated + pageUpdated,
                        skipAlreadySynced: options.skipAlreadySynced
                    )
                    if progress >= target {
                        break
                    }

                    let exists = existingIDs.contains(tweet.id)
                    if exists, options.skipAlreadySynced {
                        localStreak += 1
                        pageSkipped += 1
                        if stopAfterSkipStreak,
                           BookmarkSyncMath.shouldStopCatchUp(
                               skipAlreadySynced: true,
                               consecutiveSkips: localStreak
                           ) {
                            hitSkipStreak = true
                            break
                        }
                        continue
                    }

                    localStreak = 0
                    let upsertOutcome = try BookmarkQueries.upsertRemoteBookmark(db: db, tweet: tweet)
                    switch upsertOutcome {
                    case .inserted: pageImported += 1
                    case .restored: pageRestored += 1
                    case .updated: pageUpdated += 1
                    case .unchanged: pageSkipped += 1
                    }
                    pageOutcomes.append((tweet, upsertOutcome))
                }

                return PageProcessResult(
                    outcomes: pageOutcomes,
                    skipped: pageSkipped,
                    consecutiveSkips: localStreak,
                    hitSkipStreak: hitSkipStreak
                )
            }

            consecutiveSkips = pageResult.consecutiveSkips
            result.skipped = baselineSkipped + pageResult.skipped

            if pageResult.hitSkipStreak {
                outcome.stoppedAtSkipStreak = true
                result.stoppedAtKnownFrontier = true
            }

            for item in pageResult.outcomes {
                switch item.outcome {
                case .inserted: result.imported += 1
                case .updated: result.updated += 1
                case .restored: result.restored += 1
                case .unchanged: break
                }

                let shouldDelete = options.deleteFromXAfterSync
                    && (item.outcome == .inserted || item.outcome == .restored
                        || (!options.skipAlreadySynced && item.outcome == .updated))
                if shouldDelete {
                    phase = .deletingRemote
                    do {
                        try await deleteRemote(transport: transport, tweetID: item.tweet.id)
                        result.deletedFromX += 1
                    } catch {
                        result.failedDeletes += 1
                    }
                }
            }

            if outcome.stoppedAtSkipStreak {
                outcome.nextCursor = page.nextToken
                break pageLoop
            }

            if BookmarkSyncMath.batchProgress(result, skipAlreadySynced: options.skipAlreadySynced) >= target {
                outcome.nextCursor = paginationToken ?? page.nextToken
                break
            }

            guard let next = page.nextToken, !next.isEmpty else {
                outcome.reachedRemoteEnd = true
                outcome.nextCursor = nil
                break
            }
            if next == paginationToken {
                outcome.reachedRemoteEnd = true
                outcome.nextCursor = nil
                break
            }
            paginationToken = next
            outcome.nextCursor = next
        }

        return outcome
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

private extension BookmarkSyncMath {
    static func batchProgress(
        imported: Int,
        restored: Int,
        updated: Int,
        skipAlreadySynced: Bool
    ) -> Int {
        let gained = imported + restored
        return skipAlreadySynced ? gained : gained + updated
    }
}

enum BookmarkSyncError: LocalizedError {
    case alreadyRunning

    var errorDescription: String? {
        AppLocalization.text("sync.error.alreadyRunning")
    }
}
