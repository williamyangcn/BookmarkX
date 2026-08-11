import Foundation
import GRDB

struct Author: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "authors"

    var id: String
    var username: String
    var name: String
    var profileImageURL: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case profileImageURL = "profile_image_url"
        case updatedAt = "updated_at"
    }
}
