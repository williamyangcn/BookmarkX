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
        static let syncNewestWatermark = "settings.syncNewestWatermark"
        static let syncBackfillComplete = "settings.syncBackfillComplete"
        static let syncBackfillCursor = "settings.syncBackfillCursor"
        static let folderTaxonomyVersion = "settings.folderTaxonomyVersion"
    }

    /// Bump when the local folder taxonomy changes and existing bookmarks should be reclassified.
    static let currentFolderTaxonomyVersion = 2

    var interfaceLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: Keys.interfaceLanguage)
            AppLocalization.sync(from: interfaceLanguage)
        }
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

    /// Newest remote bookmark ID from the last successful sync (catch-up watermark).
    var syncNewestWatermark: String? {
        didSet {
            if let syncNewestWatermark, !syncNewestWatermark.isEmpty {
                UserDefaults.standard.set(syncNewestWatermark, forKey: Keys.syncNewestWatermark)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.syncNewestWatermark)
            }
        }
    }

    /// True after a sync walked to the end of the remote bookmark list.
    var syncBackfillComplete: Bool {
        didSet { UserDefaults.standard.set(syncBackfillComplete, forKey: Keys.syncBackfillComplete) }
    }

    /// Pagination cursor for resuming older bookmark backfill.
    var syncBackfillCursor: String? {
        didSet {
            if let syncBackfillCursor, !syncBackfillCursor.isEmpty {
                UserDefaults.standard.set(syncBackfillCursor, forKey: Keys.syncBackfillCursor)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.syncBackfillCursor)
            }
        }
    }

    /// Local folder taxonomy version last applied to the library.
    var folderTaxonomyVersion: Int {
        didSet { UserDefaults.standard.set(folderTaxonomyVersion, forKey: Keys.folderTaxonomyVersion) }
    }

    var syncOptions: BookmarkSyncOptions {
        BookmarkSyncOptions(
            batchSize: syncBatchSize,
            newestFirst: true,
            skipAlreadySynced: syncSkipAlreadySynced,
            deleteFromXAfterSync: syncDeleteFromXAfterSync,
            deepBackfill: false,
            backfillCursor: syncBackfillCursor,
            backfillComplete: syncBackfillComplete
        )
    }

    func resetSyncProgress() {
        syncNewestWatermark = nil
        syncBackfillComplete = false
        syncBackfillCursor = nil
    }

    init(defaults: UserDefaults = .standard) {
        let interfaceRaw = defaults.string(forKey: Keys.interfaceLanguage)
        // Prefer Simplified Chinese for the product UI when unset; keep explicit user choice.
        if let interfaceRaw, let language = AppLanguage(rawValue: interfaceRaw) {
            interfaceLanguage = language
        } else {
            interfaceLanguage = .simplifiedChinese
        }

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
        syncNewestWatermark = defaults.string(forKey: Keys.syncNewestWatermark)
        syncBackfillComplete = defaults.bool(forKey: Keys.syncBackfillComplete)
        syncBackfillCursor = defaults.string(forKey: Keys.syncBackfillCursor)
        folderTaxonomyVersion = defaults.object(forKey: Keys.folderTaxonomyVersion) as? Int ?? 0

        // One-time: if AI output is Chinese but UI was left on English, align UI language.
        let didAlign = defaults.bool(forKey: "settings.didAlignUILanguageWithAI")
        if !didAlign {
            if aiOutputLanguage == .simplifiedChinese, interfaceLanguage == .english {
                interfaceLanguage = .simplifiedChinese
            }
            defaults.set(true, forKey: "settings.didAlignUILanguageWithAI")
        }

        AppLocalization.sync(from: interfaceLanguage)
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
