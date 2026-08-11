import Foundation
import GRDB

struct Bookmark: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "bookmarks"

    var tweetID: String
    var bookmarkedAt: Date
    var folderID: String?
    var note: String?
    var isDeleted: Bool
    /// Set when imported/updated from X. Active rows with this marker are skipped on sync (IMAP-style).
    var syncedAt: Date?
    var isRead: Bool
    var readAt: Date?
    var isFavorite: Bool
    var isArchived: Bool
    var importance: BookmarkImportance
    var updatedAt: Date

    var id: String { tweetID }

    var isSynced: Bool { syncedAt != nil && !isDeleted }

    enum CodingKeys: String, CodingKey {
        case tweetID = "tweet_id"
        case bookmarkedAt = "bookmarked_at"
        case folderID = "folder_id"
        case note
        case isDeleted = "is_deleted"
        case syncedAt = "synced_at"
        case isRead = "is_read"
        case readAt = "read_at"
        case isFavorite = "is_favorite"
        case isArchived = "is_archived"
        case importance
        case updatedAt = "updated_at"
    }
}

enum BookmarkImportance: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .low: "importance.low"
        case .normal: "importance.normal"
        case .high: "importance.high"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "arrow.down"
        case .normal: "minus"
        case .high: "exclamationmark"
        }
    }
}
