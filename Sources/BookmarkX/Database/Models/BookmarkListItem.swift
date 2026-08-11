import Foundation
import GRDB

struct BookmarkListItem: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
    var tweetID: String
    var text: String
    var bookmarkedAt: Date
    /// Original post time on X (not sync / bookmark time).
    var postedAt: Date
    var authorUsername: String
    var authorName: String
    var authorProfileImageURL: String?
    var title: String?
    var summary: String?
    var category: String?
    var tagNames: String?
    var note: String?
    var folderID: String?
    var likeCount: Int
    var mediaCount: Int
    var syncedAt: Date?
    var isRead: Bool
    var readAt: Date?
    var isFavorite: Bool
    var isArchived: Bool
    var importance: BookmarkImportance

    var id: String { tweetID }

    var isSynced: Bool { syncedAt != nil }
    var tags: [String] {
        tagNames?
            .split(separator: "\u{1F}")
            .map(String.init) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case tweetID = "tweet_id"
        case text
        case bookmarkedAt = "bookmarked_at"
        case postedAt = "posted_at"
        case authorUsername = "author_username"
        case authorName = "author_name"
        case authorProfileImageURL = "author_profile_image_url"
        case title
        case summary
        case category
        case tagNames = "tag_names"
        case note
        case folderID = "folder_id"
        case likeCount = "like_count"
        case mediaCount = "media_count"
        case syncedAt = "synced_at"
        case isRead = "is_read"
        case readAt = "read_at"
        case isFavorite = "is_favorite"
        case isArchived = "is_archived"
        case importance
    }
}

/// Time buckets for the bookmark list, keyed by post time.
enum BookmarkTimeGroup: Hashable, Comparable, Sendable {
    case today
    case yesterday
    case last7Days
    case last15Days
    case lastMonth
    case thisYear
    case lastYear
    case year(Int)

    var sortIndex: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .last7Days: 2
        case .last15Days: 3
        case .lastMonth: 4
        case .thisYear: 5
        case .lastYear: 6
        case .year(let year): 1_000_000 - year
        }
    }

    static func < (lhs: BookmarkTimeGroup, rhs: BookmarkTimeGroup) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    var title: String {
        switch self {
        case .today:
            AppLocalization.text("bookmarks.section.today")
        case .yesterday:
            AppLocalization.text("bookmarks.section.yesterday")
        case .last7Days:
            AppLocalization.text("bookmarks.section.last7Days")
        case .last15Days:
            AppLocalization.text("bookmarks.section.last15Days")
        case .lastMonth:
            AppLocalization.text("bookmarks.section.lastMonth")
        case .thisYear:
            AppLocalization.text("bookmarks.section.thisYear")
        case .lastYear:
            AppLocalization.text("bookmarks.section.lastYear")
        case .year(let year):
            String(year)
        }
    }

    static func group(for date: Date, now: Date = .now, calendar: Calendar = .current) -> BookmarkTimeGroup {
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        let startOfToday = calendar.startOfDay(for: now)
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let fifteenDaysAgo = calendar.date(byAdding: .day, value: -15, to: startOfToday),
              let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: startOfToday)
        else {
            return .thisYear
        }

        if date >= sevenDaysAgo {
            return .last7Days
        }
        if date >= fifteenDaysAgo {
            return .last15Days
        }
        if date >= oneMonthAgo {
            return .lastMonth
        }

        let postYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        if postYear == currentYear {
            return .thisYear
        }
        if postYear == currentYear - 1 {
            return .lastYear
        }
        return .year(postYear)
    }
}
