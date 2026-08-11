import Foundation
import GRDB

struct AppDatabase: Sendable {
    let dbWriter: any DatabaseWriter

    static func makeShared() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("BookmarkX", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent("bookmarkx.sqlite")
        return try make(at: databaseURL)
    }

    static func makeInMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace(options: .profile) { _ in }
        }
        let queue = try DatabaseQueue(configuration: configuration)
        let database = AppDatabase(dbWriter: queue)
        try database.migrator.migrate(queue)
        return database
    }

    static func make(at url: URL) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) { event in
                print("[SQL] \(event)")
            }
        }
        #endif

        let pool = try DatabasePool(path: url.path, configuration: configuration)
        let database = AppDatabase(dbWriter: pool)
        try database.migrator.migrate(pool)
        return database
    }

    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "authors") { table in
                table.column("id", .text).primaryKey()
                table.column("username", .text).notNull()
                table.column("name", .text).notNull()
                table.column("profile_image_url", .text)
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "tweets") { table in
                table.column("id", .text).primaryKey()
                table.column("author_id", .text).notNull().references("authors", onDelete: .cascade)
                table.column("text", .text).notNull()
                table.column("lang", .text)
                table.column("created_at", .datetime).notNull()
                table.column("like_count", .integer).notNull().defaults(to: 0)
                table.column("retweet_count", .integer).notNull().defaults(to: 0)
                table.column("reply_count", .integer).notNull().defaults(to: 0)
                table.column("quote_count", .integer).notNull().defaults(to: 0)
                table.column("conversation_id", .text)
                table.column("raw_json", .text)
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "tweets_author_id_idx", on: "tweets", columns: ["author_id"])
            try db.create(index: "tweets_created_at_idx", on: "tweets", columns: ["created_at"])

            try db.create(table: "media") { table in
                table.column("id", .text).primaryKey()
                table.column("tweet_id", .text).notNull().references("tweets", onDelete: .cascade)
                table.column("type", .text).notNull()
                table.column("url", .text)
                table.column("preview_image_url", .text)
                table.column("local_path", .text)
                table.column("width", .integer)
                table.column("height", .integer)
                table.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "media_tweet_id_idx", on: "media", columns: ["tweet_id"])

            try db.create(table: "folders") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("parent_id", .text).references("folders", onDelete: .setNull)
                table.column("color_hex", .text)
                table.column("sort_order", .integer).notNull().defaults(to: 0)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "bookmarks") { table in
                table.column("tweet_id", .text).primaryKey().references("tweets", onDelete: .cascade)
                table.column("bookmarked_at", .datetime).notNull()
                table.column("folder_id", .text).references("folders", onDelete: .setNull)
                table.column("note", .text)
                table.column("is_deleted", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "bookmarks_folder_id_idx", on: "bookmarks", columns: ["folder_id"])
            try db.create(index: "bookmarks_bookmarked_at_idx", on: "bookmarks", columns: ["bookmarked_at"])

            try db.create(table: "tags") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull().unique()
                table.column("color_hex", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "bookmark_tags") { table in
                table.column("tweet_id", .text).notNull().references("bookmarks", onDelete: .cascade)
                table.column("tag_id", .text).notNull().references("tags", onDelete: .cascade)
                table.column("is_ai_generated", .boolean).notNull().defaults(to: false)
                table.primaryKey(["tweet_id", "tag_id"])
            }

            try db.create(table: "ai_results") { table in
                table.column("tweet_id", .text).primaryKey().references("bookmarks", onDelete: .cascade)
                table.column("summary", .text)
                table.column("category", .text)
                table.column("model", .text)
                table.column("is_summary_manual", .boolean).notNull().defaults(to: false)
                table.column("is_category_manual", .boolean).notNull().defaults(to: false)
                table.column("processed_at", .datetime)
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "sync_cursors") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(virtualTable: "tweets_fts", using: FTS5()) { table in
                table.synchronize(withTable: "tweets")
                table.column("text")
                table.tokenizer = .unicode61(diacritics: .remove)
            }
        }

        // IMAP-style sync markers: active synced rows are skipped until locally deleted.
        migrator.registerMigration("v2_imap_sync_markers") { db in
            try db.alter(table: "bookmarks") { table in
                table.add(column: "synced_at", .datetime)
            }
            try db.execute(
                sql: """
                UPDATE bookmarks
                SET synced_at = bookmarked_at
                WHERE is_deleted = 0 AND synced_at IS NULL
                """
            )
            try db.create(
                index: "bookmarks_synced_at_idx",
                on: "bookmarks",
                columns: ["synced_at"]
            )
            try db.create(
                index: "bookmarks_is_deleted_idx",
                on: "bookmarks",
                columns: ["is_deleted"]
            )
        }

        migrator.registerMigration("v3_ai_titles") { db in
            try db.alter(table: "ai_results") { table in
                table.add(column: "title", .text)
            }
        }

        migrator.registerMigration("v4_remove_sample_bookmarks") { db in
            let sampleIDs = try String.fetchAll(
                db,
                sql: """
                SELECT id FROM tweets
                WHERE id LIKE 'sample-tweet-%' OR author_id = 'sample-author'
                """
            )
            guard !sampleIDs.isEmpty else { return }

            // Some early v1 databases were created without effective cascade
            // actions. Delete children explicitly before their parent tweets.
            for tweetID in sampleIDs {
                try db.execute(
                    sql: "DELETE FROM bookmark_tags WHERE tweet_id = ?",
                    arguments: [tweetID]
                )
                try db.execute(
                    sql: "DELETE FROM ai_results WHERE tweet_id = ?",
                    arguments: [tweetID]
                )
                try db.execute(
                    sql: "DELETE FROM media WHERE tweet_id = ?",
                    arguments: [tweetID]
                )
                try db.execute(
                    sql: "DELETE FROM bookmarks WHERE tweet_id = ?",
                    arguments: [tweetID]
                )
            }
            try db.execute(
                sql: """
                DELETE FROM tweets
                WHERE id LIKE 'sample-tweet-%' OR author_id = 'sample-author'
                """
            )
            try db.execute(
                sql: "DELETE FROM authors WHERE id = 'sample-author'"
            )
        }

        migrator.registerMigration("v5_mailbox_state") { db in
            try db.alter(table: "bookmarks") { table in
                table.add(column: "is_read", .boolean).notNull().defaults(to: false)
                table.add(column: "read_at", .datetime)
                table.add(column: "is_favorite", .boolean).notNull().defaults(to: false)
                table.add(column: "is_archived", .boolean).notNull().defaults(to: false)
                table.add(column: "importance", .integer).notNull().defaults(to: 1)
            }
            try db.execute(
                sql: """
                UPDATE bookmarks
                SET is_archived = CASE WHEN folder_id IS NULL THEN 0 ELSE 1 END
                """
            )
            try db.execute(
                sql: """
                UPDATE folders
                SET color_hex = CASE (sort_order % 8)
                    WHEN 0 THEN '#FF5A5F'
                    WHEN 1 THEN '#FF9500'
                    WHEN 2 THEN '#FFD60A'
                    WHEN 3 THEN '#34C759'
                    WHEN 4 THEN '#00C7BE'
                    WHEN 5 THEN '#0A84FF'
                    WHEN 6 THEN '#5E5CE6'
                    ELSE '#BF5AF2'
                END
                WHERE color_hex IS NULL OR color_hex = ''
                """
            )
            try db.create(
                index: "bookmarks_mailbox_state_idx",
                on: "bookmarks",
                columns: ["is_deleted", "is_read", "is_favorite", "folder_id"]
            )
        }

        migrator.registerMigration("v6_bookmark_full_text_search") { db in
            try db.execute(
                sql: """
                CREATE VIRTUAL TABLE bookmark_search USING fts5(
                    tweet_id UNINDEXED,
                    title,
                    text,
                    summary,
                    category,
                    tags,
                    author,
                    note,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """
            )
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
                WHERE b.is_deleted = 0
                """
            )
        }

        // Remove GraphQL false positives (t.co URLs / unknown authors) from earlier sync bugs.
        migrator.registerMigration("v7_purge_invalid_bookmarks") { db in
            try db.execute(
                sql: """
                DELETE FROM bookmark_search
                WHERE tweet_id IN (
                    SELECT id FROM tweets
                    WHERE author_id = 'unknown'
                       OR id LIKE 'http%'
                       OR id GLOB '*[^0-9]*'
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM bookmark_tags
                WHERE tweet_id IN (
                    SELECT id FROM tweets
                    WHERE author_id = 'unknown'
                       OR id LIKE 'http%'
                       OR id GLOB '*[^0-9]*'
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM ai_results
                WHERE tweet_id IN (
                    SELECT id FROM tweets
                    WHERE author_id = 'unknown'
                       OR id LIKE 'http%'
                       OR id GLOB '*[^0-9]*'
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM media
                WHERE tweet_id IN (
                    SELECT id FROM tweets
                    WHERE author_id = 'unknown'
                       OR id LIKE 'http%'
                       OR id GLOB '*[^0-9]*'
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM bookmarks
                WHERE tweet_id IN (
                    SELECT id FROM tweets
                    WHERE author_id = 'unknown'
                       OR id LIKE 'http%'
                       OR id GLOB '*[^0-9]*'
                )
                """
            )
            try db.execute(
                sql: """
                DELETE FROM tweets
                WHERE author_id = 'unknown'
                   OR id LIKE 'http%'
                   OR id GLOB '*[^0-9]*'
                """
            )
            try db.execute(
                sql: """
                DELETE FROM authors
                WHERE (id = 'unknown' OR username = 'unknown')
                  AND NOT EXISTS (
                      SELECT 1 FROM tweets WHERE tweets.author_id = authors.id
                  )
                """
            )
        }

        return migrator
    }
}
