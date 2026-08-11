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
}
