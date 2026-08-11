import Foundation
import GRDB

struct Folder: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "folders"

    var id: String
    var name: String
    var parentID: String?
    var colorHex: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
