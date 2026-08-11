import Foundation

enum KeychainAccount: String, Sendable, Codable, CaseIterable {
    case xAccessToken = "x.accessToken"
    case xRefreshToken = "x.refreshToken"
    case xUserID = "x.userID"
    case xUsername = "x.username"
    case xAuthCookie = "x.authCookie"
    case xCT0 = "x.ct0"
    case xAuthMethod = "x.authMethod"
    case grokAPIKey = "grok.apiKey"
}

enum XAuthMethod: String, Sendable {
    case oauth
    case webSession
}

/// Local credential vault under Application Support (sandbox container).
/// Avoids macOS Keychain entirely — ad-hoc Debug builds hit `errSecMissingEntitlement` (-34018).
struct KeychainStore: Sendable {
    static let shared = KeychainStore()

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? Self.defaultDirectory())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("BookmarkX", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("credentials.plist")
        }
    }

    func save(_ value: String, for account: KeychainAccount) throws {
        lock.lock()
        defer { lock.unlock() }

        var values = (try? readAllUnlocked()) ?? [:]
        values[account.rawValue] = value
        try writeAllUnlocked(values)
    }

    func load(_ account: KeychainAccount) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        let values = try readAllUnlocked()
        let value = values[account.rawValue]
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    func delete(_ account: KeychainAccount) throws {
        lock.lock()
        defer { lock.unlock() }

        var values = (try? readAllUnlocked()) ?? [:]
        values.removeValue(forKey: account.rawValue)
        try writeAllUnlocked(values)
    }

    func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try writeAllUnlocked([:])
    }

    func clearXCredentials() throws {
        lock.lock()
        defer { lock.unlock() }

        var values = (try? readAllUnlocked()) ?? [:]
        for account in [
            KeychainAccount.xAccessToken,
            .xRefreshToken,
            .xUserID,
            .xUsername,
            .xAuthCookie,
            .xCT0,
            .xAuthMethod
        ] {
            values.removeValue(forKey: account.rawValue)
        }
        try writeAllUnlocked(values)
    }

    var hasXSession: Bool {
        let cookie = (try? load(.xAuthCookie))?.isEmpty == false
        let oauth = (try? load(.xAccessToken))?.isEmpty == false
        return cookie || oauth
    }

    // MARK: - File IO

    private static func defaultDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("BookmarkX", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func readAllUnlocked() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let values = object as? [String: String] else {
            return [:]
        }
        return values
    }

    private func writeAllUnlocked(_ values: [String: String]) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .binary,
            options: 0
        )
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    case ioFailed(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Credential store error: \(status)"
        case .invalidData:
            "Credential store returned invalid data"
        case .ioFailed(let message):
            message
        }
    }
}
