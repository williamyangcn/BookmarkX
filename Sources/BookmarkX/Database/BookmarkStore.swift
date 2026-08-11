import Foundation
import GRDB
import Observation

@Observable
@MainActor
final class BookmarkStore {
    private let database: AppDatabase

    private(set) var items: [BookmarkListItem] = []
    private(set) var folders: [Folder] = []
    private(set) var folderUnreadCounts: [String: Int] = [:]
    private(set) var tags: [Tag] = []
    private(set) var totalCount = 0
    private(set) var unreadCount = 0
    private(set) var favoriteCount = 0
    private(set) var importantCount = 0

    init(database: AppDatabase) {
        self.database = database
    }

    func reload(searchText: String = "") async throws {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = try await database.dbWriter.read { db in
            try BookmarkQueries.loadSnapshot(db: db, searchText: query)
        }

        self.items = snapshot.items
        self.folders = snapshot.folders
        self.folderUnreadCounts = snapshot.folderUnreadCounts
        self.tags = snapshot.tags
        self.totalCount = snapshot.totalCount
        self.unreadCount = snapshot.unreadCount
        self.favoriteCount = snapshot.favoriteCount
        self.importantCount = snapshot.importantCount
    }

    func upsertSampleBookmark() throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.insertSampleBookmark(db: db)
        }
    }

    func createFolder(named name: String) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.createFolder(db: db, named: name)
        }
    }

    func moveBookmark(tweetID: String, toFolderID folderID: String?) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.moveBookmark(db: db, tweetID: tweetID, toFolderID: folderID)
        }
    }

    func updateNote(tweetID: String, note: String?) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.updateNote(db: db, tweetID: tweetID, note: note)
        }
    }

    func setRead(tweetID: String, isRead: Bool) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.setRead(db: db, tweetID: tweetID, isRead: isRead)
        }
    }

    func setFavorite(tweetID: String, isFavorite: Bool) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.setFavorite(
                db: db,
                tweetID: tweetID,
                isFavorite: isFavorite
            )
        }
    }

    func setImportance(tweetID: String, importance: BookmarkImportance) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.setImportance(
                db: db,
                tweetID: tweetID,
                importance: importance
            )
        }
    }

    func setArchived(tweetID: String, isArchived: Bool) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.setArchived(
                db: db,
                tweetID: tweetID,
                isArchived: isArchived
            )
        }
    }

    /// Move all locally-read bookmarks into Archive (used when re-entering Inbox).
    func archiveReadBookmarks() throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.archiveReadBookmarks(db: db)
        }
    }

    /// Soft-delete locally (IMAP-style). Cleared from the active mailbox; can re-sync from X later.
    func deleteLocally(tweetID: String) throws {
        try database.dbWriter.write { db in
            try BookmarkQueries.softDeleteBookmark(db: db, tweetID: tweetID)
        }
    }

    func pendingEnrichmentItems() async throws -> [BookmarkEnrichmentItem] {
        try await database.dbWriter.read { db in
            try BookmarkQueries.fetchPendingEnrichmentItems(db: db)
        }
    }

    /// All active synced bookmarks — used for force reclassify / folder rebuild.
    func allEnrichmentItems() async throws -> [BookmarkEnrichmentItem] {
        try await database.dbWriter.read { db in
            try BookmarkQueries.fetchAllEnrichmentItems(db: db)
        }
    }

    func folderNames() async throws -> [String] {
        try await database.dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM folders ORDER BY sort_order, name")
        }
    }

    /// Drop folders that no longer contain any non-deleted bookmarks.
    func pruneEmptyFolders() async throws {
        try await database.dbWriter.write { db in
            try db.execute(
                sql: """
                DELETE FROM folders
                WHERE id NOT IN (
                    SELECT DISTINCT folder_id FROM bookmarks
                    WHERE folder_id IS NOT NULL AND is_deleted = 0
                )
                """
            )
        }
    }

    func saveEnrichment(
        tweetID: String,
        enrichment: GrokEnrichment
    ) async throws {
        try await database.dbWriter.write { db in
            try BookmarkQueries.saveEnrichment(
                db: db,
                tweetID: tweetID,
                enrichment: enrichment
            )
        }
    }

    /// Fix placeholder / junk AI titles without re-running full classification.
    @discardableResult
    func repairWeakTitles() async throws -> Int {
        try await database.dbWriter.write { db in
            try BookmarkQueries.repairWeakTitles(db: db)
        }
    }
}

struct BookmarkEnrichmentItem: Sendable, Equatable {
    var tweetID: String
    var text: String
    var authorUsername: String
    var hasMedia: Bool = false
    var currentTitle: String? = nil
}

enum BookmarkUpsertOutcome: Equatable {
    case inserted
    case updated
    case restored
    case unchanged
}

enum BookmarkQueries {
    struct Snapshot: Sendable {
        var items: [BookmarkListItem]
        var folders: [Folder]
        var folderUnreadCounts: [String: Int]
        var tags: [Tag]
        var totalCount: Int
        var unreadCount: Int
        var favoriteCount: Int
        var importantCount: Int
    }

    static func loadSnapshot(db: Database, searchText: String) throws -> Snapshot {
        struct UnreadRow: Decodable, FetchableRecord {
            var folderID: String
            var count: Int
            enum CodingKeys: String, CodingKey {
                case folderID = "folder_id"
                case count
            }
        }
        let unreadRows = try UnreadRow.fetchAll(
            db,
            sql: """
            SELECT folder_id, COUNT(*) AS count
            FROM bookmarks
            WHERE is_deleted = 0 AND is_read = 0 AND folder_id IS NOT NULL
            GROUP BY folder_id
            """
        )
        return Snapshot(
            items: try fetchItems(db: db, searchText: searchText),
            folders: try Folder.order(Column("sort_order"), Column("name")).fetchAll(db),
            folderUnreadCounts: Dictionary(uniqueKeysWithValues: unreadRows.map { ($0.folderID, $0.count) }),
            tags: try Tag.order(Column("name")).fetchAll(db),
            totalCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bookmarks WHERE is_deleted = 0"
            ) ?? 0,
            unreadCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bookmarks WHERE is_deleted = 0 AND is_read = 0"
            ) ?? 0,
            favoriteCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bookmarks WHERE is_deleted = 0 AND is_favorite = 1"
            ) ?? 0,
            importantCount: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM bookmarks WHERE is_deleted = 0 AND importance = 2"
            ) ?? 0
        )
    }

    static func insertSampleBookmark(db: Database) throws {
        let now = Date()
        let author = Author(
            id: "sample-author",
            username: "bookmarkx",
            name: "BookmarkX",
            profileImageURL: nil,
            updatedAt: now
        )
        try author.save(db)

        let tweet = Tweet(
            id: "sample-tweet-\(UUID().uuidString)",
            authorID: author.id,
            text: "Welcome to BookmarkX. Your X bookmarks will appear here after sync.",
            lang: "en",
            createdAt: now,
            likeCount: 0,
            retweetCount: 0,
            replyCount: 0,
            quoteCount: 0,
            conversationID: nil,
            rawJSON: nil,
            updatedAt: now
        )
        try tweet.save(db)

        let bookmark = Bookmark(
            tweetID: tweet.id,
            bookmarkedAt: now,
            folderID: nil,
            note: nil,
            isDeleted: false,
            syncedAt: now,
            isRead: false,
            readAt: nil,
            isFavorite: false,
            isArchived: false,
            importance: .normal,
            updatedAt: now
        )
        try bookmark.save(db)

        let ai = AIResult(
            tweetID: tweet.id,
            title: "Welcome to BookmarkX",
            summary: "Welcome sample bookmark for verifying the local database.",
            category: "Getting Started",
            model: "local-sample",
            isSummaryManual: false,
            isCategoryManual: false,
            processedAt: now,
            updatedAt: now
        )
        try ai.save(db)
        try refreshSearchIndex(db: db, tweetID: tweet.id)
    }

    static func createFolder(db: Database, named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let maxOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) FROM folders") ?? -1
        let folder = Folder(
            id: UUID().uuidString,
            name: trimmed,
            parentID: nil,
            colorHex: folderColorHex(for: maxOrder + 1),
            sortOrder: maxOrder + 1,
            createdAt: now,
            updatedAt: now
        )
        try folder.insert(db)
    }

    static func moveBookmark(db: Database, tweetID: String, toFolderID folderID: String?) throws {
        let now = Date()
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET folder_id = ?, is_archived = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [folderID, folderID != nil, now, tweetID]
        )

        // Manual folder choice wins over future AI/local auto-classification.
        let folderName: String?
        if let folderID {
            folderName = try String.fetchOne(
                db,
                sql: "SELECT name FROM folders WHERE id = ? LIMIT 1",
                arguments: [folderID]
            )
        } else {
            folderName = nil
        }

        if var existing = try AIResult.fetchOne(db, key: tweetID) {
            existing.category = folderName
            existing.isCategoryManual = true
            existing.updatedAt = now
            try existing.save(db)
        } else {
            let result = AIResult(
                tweetID: tweetID,
                title: nil,
                summary: nil,
                category: folderName,
                model: "manual",
                isSummaryManual: false,
                isCategoryManual: true,
                processedAt: now,
                updatedAt: now
            )
            try result.insert(db)
        }
        try refreshSearchIndex(db: db, tweetID: tweetID)
    }

    static func updateNote(db: Database, tweetID: String, note: String?) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET note = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [note, Date(), tweetID]
        )
        try refreshSearchIndex(db: db, tweetID: tweetID)
    }

    static func setRead(db: Database, tweetID: String, isRead: Bool) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET is_read = ?, read_at = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [isRead, isRead ? Date() : nil, Date(), tweetID]
        )
    }

    static func setFavorite(db: Database, tweetID: String, isFavorite: Bool) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET is_favorite = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [isFavorite, Date(), tweetID]
        )
    }

    static func setImportance(
        db: Database,
        tweetID: String,
        importance: BookmarkImportance
    ) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET importance = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [importance.rawValue, Date(), tweetID]
        )
    }

    static func setArchived(db: Database, tweetID: String, isArchived: Bool) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET is_archived = ?, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [isArchived, Date(), tweetID]
        )
    }

    static func archiveReadBookmarks(db: Database) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET is_archived = 1, updated_at = ?
            WHERE is_deleted = 0 AND is_read = 1 AND is_archived = 0
            """,
            arguments: [Date()]
        )
    }

    /// Soft-delete: hide locally and clear sync marker so a later sync can re-import from X.
    static func softDeleteBookmark(db: Database, tweetID: String) throws {
        try db.execute(
            sql: """
            UPDATE bookmarks
            SET is_deleted = 1, synced_at = NULL, updated_at = ?
            WHERE tweet_id = ?
            """,
            arguments: [Date(), tweetID]
        )
        try db.execute(
            sql: "DELETE FROM bookmark_search WHERE tweet_id = ?",
            arguments: [tweetID]
        )
    }

    static func fetchPendingEnrichmentItems(db: Database) throws -> [BookmarkEnrichmentItem] {
        struct Row: Decodable, FetchableRecord {
            var tweetID: String
            var text: String
            var authorUsername: String
            var hasMedia: Bool
            var currentTitle: String?

            enum CodingKeys: String, CodingKey {
                case tweetID = "tweet_id"
                case text
                case authorUsername = "author_username"
                case hasMedia = "has_media"
                case currentTitle = "current_title"
            }
        }

        return try Row.fetchAll(
            db,
            sql: """
            SELECT
                b.tweet_id AS tweet_id,
                t.text AS text,
                a.username AS author_username,
                EXISTS(SELECT 1 FROM media m WHERE m.tweet_id = b.tweet_id) AS has_media,
                ai.title AS current_title
            FROM bookmarks b
            JOIN tweets t ON t.id = b.tweet_id
            JOIN authors a ON a.id = t.author_id
            LEFT JOIN ai_results ai ON ai.tweet_id = b.tweet_id
            WHERE b.is_deleted = 0
              AND b.synced_at IS NOT NULL
              AND (
                    ai.tweet_id IS NULL
                 OR ai.processed_at IS NULL
                 OR COALESCE(ai.title, '') = ''
                 OR COALESCE(ai.summary, '') = ''
                 OR COALESCE(ai.category, '') = ''
              )
            ORDER BY b.bookmarked_at DESC
            """
        ).map {
            BookmarkEnrichmentItem(
                tweetID: $0.tweetID,
                text: $0.text,
                authorUsername: $0.authorUsername,
                hasMedia: $0.hasMedia,
                currentTitle: $0.currentTitle
            )
        }
    }

    static func fetchAllEnrichmentItems(db: Database) throws -> [BookmarkEnrichmentItem] {
        struct Row: Decodable, FetchableRecord {
            var tweetID: String
            var text: String
            var authorUsername: String
            var hasMedia: Bool
            var currentTitle: String?

            enum CodingKeys: String, CodingKey {
                case tweetID = "tweet_id"
                case text
                case authorUsername = "author_username"
                case hasMedia = "has_media"
                case currentTitle = "current_title"
            }
        }

        return try Row.fetchAll(
            db,
            sql: """
            SELECT
                b.tweet_id AS tweet_id,
                t.text AS text,
                a.username AS author_username,
                EXISTS(SELECT 1 FROM media m WHERE m.tweet_id = b.tweet_id) AS has_media,
                ai.title AS current_title
            FROM bookmarks b
            JOIN tweets t ON t.id = b.tweet_id
            JOIN authors a ON a.id = t.author_id
            LEFT JOIN ai_results ai ON ai.tweet_id = b.tweet_id
            WHERE b.is_deleted = 0
              AND b.synced_at IS NOT NULL
            ORDER BY b.bookmarked_at DESC
            """
        ).map {
            BookmarkEnrichmentItem(
                tweetID: $0.tweetID,
                text: $0.text,
                authorUsername: $0.authorUsername,
                hasMedia: $0.hasMedia,
                currentTitle: $0.currentTitle
            )
        }
    }

    static func repairWeakTitles(db: Database) throws -> Int {
        struct Row: Decodable, FetchableRecord {
            var tweetID: String
            var text: String
            var authorUsername: String
            var hasMedia: Bool
            var title: String?
            var summary: String?

            enum CodingKeys: String, CodingKey {
                case tweetID = "tweet_id"
                case text
                case authorUsername = "author_username"
                case hasMedia = "has_media"
                case title
                case summary
            }
        }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT
                b.tweet_id AS tweet_id,
                t.text AS text,
                a.username AS author_username,
                EXISTS(SELECT 1 FROM media m WHERE m.tweet_id = b.tweet_id) AS has_media,
                ai.title AS title,
                ai.summary AS summary
            FROM bookmarks b
            JOIN tweets t ON t.id = b.tweet_id
            JOIN authors a ON a.id = t.author_id
            JOIN ai_results ai ON ai.tweet_id = b.tweet_id
            WHERE b.is_deleted = 0
            """
        )

        var fixed = 0
        let now = Date()
        for row in rows {
            let titleNeedsFix = LocalBookmarkClassifier.isWeakTitle(row.title ?? "")
            let rawSummary = row.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summaryNeedsFix = LocalBookmarkClassifier.isWeakTitle(rawSummary)
                || rawSummary.lowercased().hasPrefix("http")
                || rawSummary == "（无文字内容）"
            guard titleNeedsFix || summaryNeedsFix else { continue }

            let newTitle = LocalBookmarkClassifier.makeTitle(
                text: row.text,
                authorUsername: row.authorUsername,
                hasMedia: row.hasMedia
            )
            let newSummary = summaryNeedsFix
                ? LocalBookmarkClassifier.makeSummary(text: row.text)
                : (row.summary ?? LocalBookmarkClassifier.makeSummary(text: row.text))

            try db.execute(
                sql: """
                UPDATE ai_results
                SET title = ?, summary = ?, updated_at = ?
                WHERE tweet_id = ?
                """,
                arguments: [
                    titleNeedsFix ? newTitle : (row.title ?? newTitle),
                    newSummary,
                    now,
                    row.tweetID
                ]
            )
            fixed += 1
        }
        return fixed
    }

    static func saveEnrichment(
        db: Database,
        tweetID: String,
        enrichment: GrokEnrichment
    ) throws {
        let now = Date()
        let existing = try AIResult.fetchOne(db, key: tweetID)
        let result = AIResult(
            tweetID: tweetID,
            title: enrichment.title,
            summary: existing?.isSummaryManual == true ? existing?.summary : enrichment.summary,
            category: existing?.isCategoryManual == true ? existing?.category : enrichment.category,
            model: enrichment.model,
            isSummaryManual: existing?.isSummaryManual ?? false,
            isCategoryManual: existing?.isCategoryManual ?? false,
            processedAt: now,
            updatedAt: now
        )
        try result.save(db)

        let category = enrichment.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty, existing?.isCategoryManual != true {
            let folderID: String
            if let existingFolderID = try String.fetchOne(
                db,
                sql: "SELECT id FROM folders WHERE name = ? COLLATE NOCASE LIMIT 1",
                arguments: [category]
            ) {
                folderID = existingFolderID
            } else {
                folderID = UUID().uuidString
                let maxOrder = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(MAX(sort_order), -1) FROM folders"
                ) ?? -1
                let folder = Folder(
                    id: folderID,
                    name: category,
                    parentID: nil,
                    colorHex: folderColorHex(for: maxOrder + 1),
                    sortOrder: maxOrder + 1,
                    createdAt: now,
                    updatedAt: now
                )
                try folder.insert(db)
            }
            try db.execute(
                sql: """
                UPDATE bookmarks
                SET folder_id = ?, is_archived = 1, updated_at = ?
                WHERE tweet_id = ?
                """,
                arguments: [folderID, now, tweetID]
            )
        }

        // Refresh only AI-generated tags; preserve manually attached tags.
        try db.execute(
            sql: """
            DELETE FROM bookmark_tags
            WHERE tweet_id = ? AND is_ai_generated = 1
            """,
            arguments: [tweetID]
        )

        var seen = Set<String>()
        for rawName in enrichment.tags.prefix(5) {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = name.lowercased()
            guard !name.isEmpty, seen.insert(normalized).inserted else { continue }

            let tagID: String
            if let existingTagID = try String.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1",
                arguments: [name]
            ) {
                tagID = existingTagID
            } else {
                tagID = UUID().uuidString
                let tag = Tag(
                    id: tagID,
                    name: name,
                    colorHex: nil,
                    createdAt: now,
                    updatedAt: now
                )
                try tag.insert(db)
            }

            try db.execute(
                sql: """
                INSERT OR REPLACE INTO bookmark_tags
                    (tweet_id, tag_id, is_ai_generated)
                VALUES (?, ?, 1)
                """,
                arguments: [tweetID, tagID]
            )
        }

        try refreshSearchIndex(db: db, tweetID: tweetID)
    }

    /// Active local copy (IMAP "already in mailbox").
    static func bookmarkExists(db: Database, tweetID: String) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM bookmarks WHERE tweet_id = ? AND is_deleted = 0)",
            arguments: [tweetID]
        ) ?? false
    }

    /// Batch existence check for one sync page (avoids per-tweet DB round-trips).
    static func existingBookmarkIDs(db: Database, tweetIDs: [String]) throws -> Set<String> {
        guard !tweetIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: tweetIDs.count).joined(separator: ",")
        return try Set(
            String.fetchAll(
                db,
                sql: """
                SELECT tweet_id FROM bookmarks
                WHERE is_deleted = 0 AND tweet_id IN (\(placeholders))
                """,
                arguments: StatementArguments(tweetIDs)
            )
        )
    }

    static func bookmarkRowState(db: Database, tweetID: String) throws -> (exists: Bool, isDeleted: Bool)? {
        struct Row: Decodable, FetchableRecord {
            var isDeleted: Bool
            enum CodingKeys: String, CodingKey { case isDeleted = "is_deleted" }
        }
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT is_deleted FROM bookmarks WHERE tweet_id = ?",
            arguments: [tweetID]
        ) else {
            return nil
        }
        return (true, row.isDeleted)
    }

    @discardableResult
    static func upsertRemoteBookmark(db: Database, tweet: RemoteBookmarkTweet) throws -> BookmarkUpsertOutcome {
        // Never persist GraphQL false positives (t.co URLs / unknown authors).
        let isNumericID = !tweet.id.isEmpty
            && tweet.id.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        guard isNumericID,
              tweet.authorID != "unknown",
              tweet.authorUsername != "unknown",
              !tweet.authorUsername.isEmpty
        else {
            return .unchanged
        }

        let now = Date()
        let prior = try bookmarkRowState(db: db, tweetID: tweet.id)

        let author = Author(
            id: tweet.authorID,
            username: tweet.authorUsername,
            name: tweet.authorName,
            profileImageURL: tweet.authorProfileImageURL,
            updatedAt: now
        )
        try author.save(db)

        let localTweet = Tweet(
            id: tweet.id,
            authorID: tweet.authorID,
            text: tweet.text,
            lang: tweet.lang,
            createdAt: tweet.createdAt,
            likeCount: tweet.likeCount,
            retweetCount: tweet.retweetCount,
            replyCount: tweet.replyCount,
            quoteCount: tweet.quoteCount,
            conversationID: tweet.conversationID,
            rawJSON: tweet.rawJSON,
            updatedAt: now
        )
        try localTweet.save(db)

        let outcome: BookmarkUpsertOutcome
        if let prior {
            if prior.isDeleted {
                try db.execute(
                    sql: """
                    UPDATE bookmarks
                    SET is_deleted = 0,
                        synced_at = ?,
                        bookmarked_at = ?,
                        updated_at = ?
                    WHERE tweet_id = ?
                    """,
                    arguments: [now, now, now, tweet.id]
                )
                outcome = .restored
            } else {
                try db.execute(
                    sql: """
                    UPDATE bookmarks
                    SET is_deleted = 0, synced_at = ?, updated_at = ?
                    WHERE tweet_id = ?
                    """,
                    arguments: [now, now, tweet.id]
                )
                outcome = .updated
            }
        } else {
            let bookmark = Bookmark(
                tweetID: tweet.id,
                bookmarkedAt: now,
                folderID: nil,
                note: nil,
                isDeleted: false,
                syncedAt: now,
                isRead: false,
                readAt: nil,
                isFavorite: false,
                isArchived: false,
                importance: .normal,
                updatedAt: now
            )
            try bookmark.insert(db)
            outcome = .inserted
        }

        try db.execute(sql: "DELETE FROM media WHERE tweet_id = ?", arguments: [tweet.id])
        for (index, item) in tweet.media.enumerated() {
            let media = MediaItem(
                id: item.id,
                tweetID: tweet.id,
                type: item.type,
                url: item.url,
                previewImageURL: item.previewImageURL,
                localPath: nil,
                width: item.width,
                height: item.height,
                sortOrder: index
            )
            try media.insert(db)
        }

        try refreshSearchIndex(db: db, tweetID: tweet.id)
        return outcome
    }

    private static func fetchItems(db: Database, searchText: String) throws -> [BookmarkListItem] {
        let columns = """
            b.tweet_id AS tweet_id,
            t.text AS text,
            b.bookmarked_at AS bookmarked_at,
            t.created_at AS posted_at,
            a.username AS author_username,
            a.name AS author_name,
            a.profile_image_url AS author_profile_image_url,
            ai.summary AS summary,
            ai.title AS title,
            ai.category AS category,
            (
                SELECT GROUP_CONCAT(tag.name, CHAR(31))
                FROM bookmark_tags bt
                JOIN tags tag ON tag.id = bt.tag_id
                WHERE bt.tweet_id = b.tweet_id
            ) AS tag_names,
            b.note AS note,
            b.folder_id AS folder_id,
            t.like_count AS like_count,
            COALESCE(m.media_count, 0) AS media_count,
            b.synced_at AS synced_at,
            b.is_read AS is_read,
            b.read_at AS read_at,
            b.is_favorite AS is_favorite,
            b.is_archived AS is_archived,
            b.importance AS importance
        """

        if searchText.isEmpty {
            return try BookmarkListItem.fetchAll(
                db,
                sql: """
                SELECT \(columns)
                FROM bookmarks b
                JOIN tweets t ON t.id = b.tweet_id
                JOIN authors a ON a.id = t.author_id
                LEFT JOIN ai_results ai ON ai.tweet_id = b.tweet_id
                LEFT JOIN (
                    SELECT tweet_id, COUNT(*) AS media_count
                    FROM media
                    GROUP BY tweet_id
                ) m ON m.tweet_id = b.tweet_id
                WHERE b.is_deleted = 0
                ORDER BY t.created_at DESC
                """
            )
        }

        let pattern = "\"\(searchText.replacingOccurrences(of: "\"", with: "\"\""))\""
        return try BookmarkListItem.fetchAll(
            db,
            sql: """
            SELECT \(columns)
            FROM bookmarks b
            JOIN tweets t ON t.id = b.tweet_id
            JOIN authors a ON a.id = t.author_id
            JOIN bookmark_search ON bookmark_search.tweet_id = b.tweet_id
            LEFT JOIN ai_results ai ON ai.tweet_id = b.tweet_id
            LEFT JOIN (
                SELECT tweet_id, COUNT(*) AS media_count
                FROM media
                GROUP BY tweet_id
            ) m ON m.tweet_id = b.tweet_id
            WHERE b.is_deleted = 0
              AND bookmark_search MATCH ?
            ORDER BY t.created_at DESC
            """,
            arguments: [pattern]
        )
    }

    static func folderColorHex(for order: Int) -> String {
        let colors = [
            "#FF5A5F", "#FF9500", "#FFD60A", "#34C759",
            "#00C7BE", "#0A84FF", "#5E5CE6", "#BF5AF2",
        ]
        return colors[((order % colors.count) + colors.count) % colors.count]
    }

    static func refreshSearchIndex(db: Database, tweetID: String) throws {
        try db.execute(
            sql: "DELETE FROM bookmark_search WHERE tweet_id = ?",
            arguments: [tweetID]
        )

        let isActive = try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1 FROM bookmarks
                WHERE tweet_id = ? AND is_deleted = 0
            )
            """,
            arguments: [tweetID]
        ) ?? false
        guard isActive else { return }

        try db.execute(
            sql: """
            INSERT INTO bookmark_search
                (tweet_id, title, text, summary, category, tags, author, note)
            SELECT
                b.tweet_id,
                COALESCE(ai.title, ''),
                t.text,
                COALESCE(ai.summary, ''),
                COALESCE(ai.category, ''),
                COALESCE((
                    SELECT GROUP_CONCAT(tag.name, ' ')
                    FROM bookmark_tags bt
                    JOIN tags tag ON tag.id = bt.tag_id
                    WHERE bt.tweet_id = b.tweet_id
                ), ''),
                a.name || ' @' || a.username,
                COALESCE(b.note, '')
            FROM bookmarks b
            JOIN tweets t ON t.id = b.tweet_id
            JOIN authors a ON a.id = t.author_id
            LEFT JOIN ai_results ai ON ai.tweet_id = b.tweet_id
            WHERE b.tweet_id = ?
            """,
            arguments: [tweetID]
        )
    }
}
