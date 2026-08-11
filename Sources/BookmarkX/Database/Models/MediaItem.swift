import Foundation
import GRDB

struct MediaItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "media"

    var id: String
    var tweetID: String
    var type: String
    var url: String?
    var previewImageURL: String?
    var localPath: String?
    var width: Int?
    var height: Int?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case tweetID = "tweet_id"
        case type
        case url
        case previewImageURL = "preview_image_url"
        case localPath = "local_path"
        case width
        case height
        case sortOrder = "sort_order"
    }
}
