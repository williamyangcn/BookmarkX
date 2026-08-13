import XCTest
@testable import BookmarkX

final class BookmarkSyncMathTests: XCTestCase {
    func testSkippedRowsDoNotFillBatchQuota() {
        var result = BookmarkSyncResult()
        result.skipped = 100
        result.imported = 0

        XCTAssertEqual(
            BookmarkSyncMath.batchProgress(result, skipAlreadySynced: true),
            0,
            "Skipped bookmarks must not count toward the per-refresh new-bookmark target"
        )

        result.imported = 40
        result.restored = 10
        result.skipped = 200
        XCTAssertEqual(
            BookmarkSyncMath.batchProgress(result, skipAlreadySynced: true),
            50
        )
    }

    func testUpdatesCountOnlyWhenNotSkipping() {
        var result = BookmarkSyncResult()
        result.imported = 10
        result.updated = 20
        result.restored = 5

        XCTAssertEqual(
            BookmarkSyncMath.batchProgress(result, skipAlreadySynced: true),
            15
        )
        XCTAssertEqual(
            BookmarkSyncMath.batchProgress(result, skipAlreadySynced: false),
            35
        )
    }

    func testCatchUpStopsAfterConsecutiveLocalSkips() {
        XCTAssertFalse(
            BookmarkSyncMath.shouldStopCatchUp(
                skipAlreadySynced: true,
                consecutiveSkips: 7
            )
        )
        XCTAssertTrue(
            BookmarkSyncMath.shouldStopCatchUp(
                skipAlreadySynced: true,
                consecutiveSkips: 8
            )
        )
        XCTAssertFalse(
            BookmarkSyncMath.shouldStopCatchUp(
                skipAlreadySynced: false,
                consecutiveSkips: 100
            )
        )
    }

    func testCatchUpSkipStreakDoesNotBlockFurtherSamePageImports() {
        // After the streak threshold, catch-up still finishes the current page
        // (importing any remaining non-local rows) before stopping pagination.
        // This guards the mid-page hole regression: do not treat "should stop"
        // as "break out of the page loop immediately".
        XCTAssertTrue(
            BookmarkSyncMath.shouldStopCatchUp(
                skipAlreadySynced: true,
                consecutiveSkips: BookmarkSyncMath.catchUpSkipStreak
            )
        )
        XCTAssertEqual(BookmarkSyncMath.catchUpSkipStreak, 8)
    }

    func testEmptyPageIsEOFOnlyWithoutANewCursor() {
        XCTAssertTrue(
            BookmarkSyncMath.isRemoteEnd(
                tweetsEmpty: true,
                nextToken: nil,
                currentToken: "cursor-a"
            )
        )
        XCTAssertTrue(
            BookmarkSyncMath.isRemoteEnd(
                tweetsEmpty: true,
                nextToken: "cursor-a",
                currentToken: "cursor-a"
            )
        )
        XCTAssertFalse(
            BookmarkSyncMath.isRemoteEnd(
                tweetsEmpty: true,
                nextToken: "cursor-b",
                currentToken: "cursor-a"
            ),
            "A new cursor on an empty page is a hole, not the end of the remote list"
        )
        XCTAssertFalse(
            BookmarkSyncMath.isRemoteEnd(
                tweetsEmpty: false,
                nextToken: nil,
                currentToken: nil
            )
        )
    }

    func testFolderResolveDoesNotMapShortSubstring() {
        XCTAssertEqual(
            LocalBookmarkClassifier.resolveCategory("投资", existingFolders: ["商业与投资"]),
            "投资"
        )
        XCTAssertEqual(
            LocalBookmarkClassifier.resolveCategory("游戏", existingFolders: ["游戏娱乐"]),
            "游戏"
        )
        XCTAssertEqual(
            LocalBookmarkClassifier.resolveCategory("前端开发", existingFolders: ["前端开发"]),
            "前端开发"
        )
    }
}
