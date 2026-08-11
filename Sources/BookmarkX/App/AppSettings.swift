import Foundation

@Observable
final class AppSettings {
    private enum Keys {
        static let interfaceLanguage = "settings.interfaceLanguage"
        static let aiOutputLanguage = "settings.aiOutputLanguage"
        static let grokModel = "settings.grokModel"
        static let grokAccessMode = "settings.grokAccessMode"
        static let xClientID = "settings.xClientID"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let syncBatchSize = "settings.syncBatchSize"
        static let syncSkipAlreadySynced = "settings.syncSkipAlreadySynced"
        static let syncDeleteFromXAfterSync = "settings.syncDeleteFromXAfterSync"
    }

    var interfaceLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: Keys.interfaceLanguage) }
    }

    var aiOutputLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(aiOutputLanguage.rawValue, forKey: Keys.aiOutputLanguage) }
    }

    var grokModel: String {
        didSet { UserDefaults.standard.set(grokModel, forKey: Keys.grokModel) }
    }

    var grokAccessMode: GrokAccessMode {
        didSet { UserDefaults.standard.set(grokAccessMode.rawValue, forKey: Keys.grokAccessMode) }
    }

    var xClientID: String {
        didSet { UserDefaults.standard.set(xClientID, forKey: Keys.xClientID) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Number of *new* (not yet local) bookmarks to fetch per sync (1...100).
    var syncBatchSize: Int {
        didSet {
            let clamped = min(max(syncBatchSize, 1), 100)
            if clamped != syncBatchSize {
                syncBatchSize = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.syncBatchSize)
        }
    }

    /// Skip bookmarks already stored locally, then keep paging for older unfetched ones.
    var syncSkipAlreadySynced: Bool {
        didSet { UserDefaults.standard.set(syncSkipAlreadySynced, forKey: Keys.syncSkipAlreadySynced) }
    }

    /// Delete the bookmark on X after it has been saved locally.
    var syncDeleteFromXAfterSync: Bool {
        didSet { UserDefaults.standard.set(syncDeleteFromXAfterSync, forKey: Keys.syncDeleteFromXAfterSync) }
    }

    var syncOptions: BookmarkSyncOptions {
        BookmarkSyncOptions(
            batchSize: syncBatchSize,
            newestFirst: true,
            skipAlreadySynced: syncSkipAlreadySynced,
            deleteFromXAfterSync: syncDeleteFromXAfterSync
        )
    }

    init(defaults: UserDefaults = .standard) {
        let interfaceRaw = defaults.string(forKey: Keys.interfaceLanguage)
        interfaceLanguage = AppLanguage(rawValue: interfaceRaw ?? "") ?? .system

        let aiRaw = defaults.string(forKey: Keys.aiOutputLanguage)
        aiOutputLanguage = AppLanguage(rawValue: aiRaw ?? "") ?? .simplifiedChinese

        grokModel = defaults.string(forKey: Keys.grokModel) ?? "grok-4-fast"
        let modeRaw = defaults.string(forKey: Keys.grokAccessMode) ?? ""
        // Default: X Premium Grok via integrated X login (same idea as Grok).
        grokAccessMode = GrokAccessMode(rawValue: modeRaw) ?? .xPremium
        xClientID = defaults.string(forKey: Keys.xClientID) ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let storedBatch = defaults.object(forKey: Keys.syncBatchSize) as? Int
        syncBatchSize = min(max(storedBatch ?? 100, 1), 100)

        if defaults.object(forKey: Keys.syncSkipAlreadySynced) == nil {
            syncSkipAlreadySynced = true
        } else {
            syncSkipAlreadySynced = defaults.bool(forKey: Keys.syncSkipAlreadySynced)
        }

        syncDeleteFromXAfterSync = defaults.bool(forKey: Keys.syncDeleteFromXAfterSync)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .simplifiedChinese: "language.simplifiedChinese"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }
}
