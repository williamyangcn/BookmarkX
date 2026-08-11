import Foundation
import GRDB

struct Tweet: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "tweets"

    var id: String
    var authorID: String
    var text: String
    var lang: String?
    var createdAt: Date
    var likeCount: Int
    var retweetCount: Int
    var replyCount: Int
    var quoteCount: Int
    var conversationID: String?
    var rawJSON: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case text
        case lang
        case createdAt = "created_at"
        case likeCount = "like_count"
        case retweetCount = "retweet_count"
        case replyCount = "reply_count"
        case quoteCount = "quote_count"
        case conversationID = "conversation_id"
        case rawJSON = "raw_json"
        case updatedAt = "updated_at"
    }
}
