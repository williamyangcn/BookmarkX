import XCTest
@testable import BookmarkX

final class AppDatabaseTests: XCTestCase {
    @MainActor
    func testMigrationAndSampleBookmarkRoundTrip() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload()

        XCTAssertEqual(store.totalCount, 1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.authorUsername, "bookmarkx")
        XCTAssertFalse(store.items.first?.summary?.isEmpty ?? true)
    }

    @MainActor
    func testCreateFolderAndMoveBookmark() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload()
        let tweetID = try XCTUnwrap(store.items.first?.tweetID)

        try store.createFolder(named: "AI")
        try await store.reload()
        XCTAssertEqual(store.folders.count, 1)

        let folderID = try XCTUnwrap(store.folders.first?.id)
        try store.moveBookmark(tweetID: tweetID, toFolderID: folderID)
        try await store.reload()

        XCTAssertEqual(store.items.first?.folderID, folderID)
    }

    @MainActor
    func testFullTextSearchFindsBookmarkText() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload(searchText: "Welcome")

        XCTAssertEqual(store.items.count, 1)

        try await store.reload(searchText: "nonexistent-token-xyz")
        XCTAssertEqual(store.items.count, 0)
    }

    @MainActor
    func testUpdateNote() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload()
        let tweetID = try XCTUnwrap(store.items.first?.tweetID)

        try store.updateNote(tweetID: tweetID, note: "Keep this")
        try await store.reload()

        XCTAssertEqual(store.items.first?.note, "Keep this")
    }

    @MainActor
    func testLocalDeleteClearsSyncMarkerAndAllowsRestore() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload()
        let tweetID = try XCTUnwrap(store.items.first?.tweetID)
        XCTAssertTrue(store.items.first?.isSynced ?? false)

        try store.deleteLocally(tweetID: tweetID)
        try await store.reload()
        XCTAssertEqual(store.totalCount, 0)

        let existsActive = try await database.dbWriter.read { db in
            try BookmarkQueries.bookmarkExists(db: db, tweetID: tweetID)
        }
        XCTAssertFalse(existsActive)

        let remote = RemoteBookmarkTweet(
            id: tweetID,
            text: "Restored from X",
            authorID: "sample-author",
            authorUsername: "bookmarkx",
            authorName: "BookmarkX",
            authorProfileImageURL: nil,
            createdAt: Date(),
            lang: "en",
            likeCount: 0,
            retweetCount: 0,
            replyCount: 0,
            quoteCount: 0,
            conversationID: nil,
            media: [],
            rawJSON: nil
        )
        let outcome = try await database.dbWriter.write { db in
            try BookmarkQueries.upsertRemoteBookmark(db: db, tweet: remote)
        }
        XCTAssertEqual(outcome, .restored)

        try await store.reload()
        XCTAssertEqual(store.totalCount, 1)
        XCTAssertTrue(store.items.first?.isSynced ?? false)
    }

    @MainActor
    func testEnrichmentCreatesTitleCategoryFolderAndTags() async throws {
        let database = try AppDatabase.makeInMemory()
        let store = BookmarkStore(database: database)

        try store.upsertSampleBookmark()
        try await store.reload()
        let tweetID = try XCTUnwrap(store.items.first?.tweetID)

        try await store.saveEnrichment(
            tweetID: tweetID,
            enrichment: GrokEnrichment(
                title: "SwiftUI Knowledge Management",
                summary: "A concise summary.",
                category: "Development",
                tags: ["SwiftUI", "macOS", "SwiftUI"],
                model: "test-model",
                provider: .apiKey
            )
        )
        try await store.reload()

        XCTAssertEqual(store.items.first?.title, "SwiftUI Knowledge Management")
        XCTAssertEqual(store.items.first?.summary, "A concise summary.")
        XCTAssertNotNil(store.items.first?.folderID)
        XCTAssertEqual(store.folders.map(\.name), ["Development"])
        XCTAssertEqual(Set(store.tags.map(\.name)), Set(["SwiftUI", "macOS"]))
    }
}
