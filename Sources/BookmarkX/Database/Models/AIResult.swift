import Foundation
import GRDB

struct AIResult: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "ai_results"

    var tweetID: String
    var title: String?
    var summary: String?
    var category: String?
    var model: String?
    var isSummaryManual: Bool
    var isCategoryManual: Bool
    var processedAt: Date?
    var updatedAt: Date

    var id: String { tweetID }

    enum CodingKeys: String, CodingKey {
        case tweetID = "tweet_id"
        case title
        case summary
        case category
        case model
        case isSummaryManual = "is_summary_manual"
        case isCategoryManual = "is_category_manual"
        case processedAt = "processed_at"
        case updatedAt = "updated_at"
    }
}
