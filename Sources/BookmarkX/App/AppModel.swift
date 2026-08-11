import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class AppModel {
    private static let logger = Logger(
        subsystem: "com.williamyang.BookmarkX",
        category: "enrichment"
    )
    private static let autoReadDelay: Duration = .seconds(30)

    enum Phase: Equatable {
        case launching
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .launching
    private(set) var database: AppDatabase?
    private(set) var bookmarkStore: BookmarkStore?
    private(set) var syncService: BookmarkSyncService?

    var selectedSidebarItem: SidebarItem = .inbox
    var searchText = ""
    var selectedBookmarkID: String?
    var isSyncing = false
    var isEnriching = false
    var syncStatusMessage: String?

    let settings = AppSettings()
    let connectionStatus = ConnectionStatus()
    let xOAuthService = XOAuthService()
    let grokClient = GrokClient()

    @ObservationIgnored
    private var autoReadTask: Task<Void, Never>?

    /// Items marked read during the current Inbox visit — stay visible until next Inbox entry.
    private(set) var inboxSessionRetainedIDs: Set<String> = []

    func bootstrap() async {
        do {
            let database = try AppDatabase.makeShared()
            self.database = database
            self.bookmarkStore = BookmarkStore(database: database)
            self.syncService = BookmarkSyncService(database: database)
            try await bookmarkStore?.reload()
            connectionStatus.refresh(from: settings)
            // Keep login: if a session is already on disk, skip onboarding forever until sign-out.
            if connectionStatus.isXConnected {
                settings.hasCompletedOnboarding = true
            }
            await configureGrokClient()
            await seedPreviewWebSession()
            phase = .ready
            await enterInbox()
            if connectionStatus.isGrokConfigured {
                Task { await enrichPendingBookmarks() }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Toolbar refresh: sync from X when signed in, then reload local list.
    func refreshBookmarks() async {
        if connectionStatus.isXConnected {
            await syncBookmarks()
        } else {
            do {
                try await bookmarkStore?.reload(searchText: searchText)
                syncStatusMessage = String(localized: "sync.status.signInRequired")
            } catch {
                syncStatusMessage = error.localizedDescription
            }
        }
    }

    func syncBookmarks() async {
        guard let syncService else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncStatusMessage = String(localized: "sync.status.running")
        defer { isSyncing = false }

        do {
            let result = try await syncService.sync(options: settings.syncOptions)
            try await bookmarkStore?.reload(searchText: searchText)
            syncStatusMessage = String(
                format: String(localized: "sync.status.completedFormat"),
                locale: .current,
                result.imported,
                result.updated,
                result.restored,
                result.skipped,
                settings.syncBatchSize
            )
            await enrichPendingBookmarks()
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    /// Generates title, summary, category folder, and tags for all unprocessed
    /// active synced bookmarks. Existing rows are picked up once by `processed_at`.
    func enrichPendingBookmarks() async {
        guard !isEnriching, connectionStatus.isGrokConfigured else { return }
        guard let bookmarkStore else { return }

        isEnriching = true
        defer { isEnriching = false }

        do {
            await configureGrokClient()
            let items = try await bookmarkStore.pendingEnrichmentItems()
            guard !items.isEmpty else { return }

            var completed = 0
            var failed = 0
            var firstError: String?
            var useLocalFallback = false

            for item in items {
                syncStatusMessage = String(
                    format: String(localized: "enrichment.status.runningFormat"),
                    locale: .current,
                    completed + failed + 1,
                    items.count
                )
                do {
                    let enrichment: GrokEnrichment
                    if useLocalFallback {
                        enrichment = LocalBookmarkClassifier.enrich(
                            text: item.text,
                            authorUsername: item.authorUsername
                        )
                    } else {
                        do {
                            enrichment = try await grokClient.enrich(
                                tweetText: item.text,
                                authorUsername: item.authorUsername
                            )
                        } catch {
                            useLocalFallback = true
                            Self.logger.error(
                                "Grok unavailable; using local classifier: \(error.localizedDescription, privacy: .public)"
                            )
                            enrichment = LocalBookmarkClassifier.enrich(
                                text: item.text,
                                authorUsername: item.authorUsername
                            )
                        }
                    }
                    try await bookmarkStore.saveEnrichment(
                        tweetID: item.tweetID,
                        enrichment: enrichment
                    )
                    completed += 1
                } catch {
                    failed += 1
                    if firstError == nil {
                        firstError = error.localizedDescription
                        Self.logger.error("Saving enrichment failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            try await bookmarkStore.reload(searchText: searchText)
            if failed == 0 {
                syncStatusMessage = String(
                    format: String(localized: "enrichment.status.completedFormat"),
                    locale: .current,
                    completed
                )
            } else {
                syncStatusMessage = String(
                    format: String(localized: "enrichment.status.partialFormat"),
                    locale: .current,
                    completed,
                    failed,
                    firstError ?? ""
                )
            }
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    /// IMAP-style local delete. Optionally also removes the bookmark on X.
    func deleteBookmark(tweetID: String, alsoFromX: Bool) async {
        do {
            try bookmarkStore?.deleteLocally(tweetID: tweetID)
            if alsoFromX, let syncService {
                try await syncService.deleteRemoteBookmark(tweetID: tweetID)
                syncStatusMessage = String(localized: "bookmarks.deletedLocalAndX")
            } else {
                syncStatusMessage = String(localized: "bookmarks.deletedLocal")
            }
            if selectedBookmarkID == tweetID {
                selectedBookmarkID = nil
            }
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func setRead(tweetID: String, isRead: Bool) async {
        do {
            try bookmarkStore?.setRead(tweetID: tweetID, isRead: isRead)
            if isRead, selectedSidebarItem == .inbox {
                inboxSessionRetainedIDs.insert(tweetID)
            } else if !isRead {
                inboxSessionRetainedIDs.remove(tweetID)
            }
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    /// Called when opening Inbox: archive previously-read items, then show remaining unread.
    func enterInbox() async {
        do {
            try bookmarkStore?.archiveReadBookmarks()
            inboxSessionRetainedIDs.removeAll()
            selectedSidebarItem = .inbox
            try await bookmarkStore?.reload(searchText: searchText)
            if let selectedBookmarkID,
               let item = bookmarkStore?.items.first(where: { $0.tweetID == selectedBookmarkID }),
               item.isRead {
                self.selectedBookmarkID = nil
            }
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func selectSidebarItem(_ item: SidebarItem) {
        if item == .inbox {
            Task { await enterInbox() }
            return
        }
        selectedSidebarItem = item
        if !item.showsBookmarkList {
            selectedBookmarkID = nil
        }
    }

    func setFavorite(tweetID: String, isFavorite: Bool) async {
        do {
            try bookmarkStore?.setFavorite(tweetID: tweetID, isFavorite: isFavorite)
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func setImportance(tweetID: String, importance: BookmarkImportance) async {
        do {
            try bookmarkStore?.setImportance(tweetID: tweetID, importance: importance)
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func setArchived(tweetID: String, isArchived: Bool) async {
        do {
            try bookmarkStore?.setArchived(tweetID: tweetID, isArchived: isArchived)
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func selectBookmark(_ tweetID: String?) {
        selectedBookmarkID = tweetID
        scheduleAutoRead(for: tweetID)
    }

    func scheduleAutoRead(for tweetID: String?) {
        autoReadTask?.cancel()
        autoReadTask = nil
        guard let tweetID else { return }
        guard let item = bookmarkStore?.items.first(where: { $0.tweetID == tweetID }),
              !item.isRead
        else { return }

        autoReadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoReadDelay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.selectedBookmarkID == tweetID else { return }
            await self.setRead(tweetID: tweetID, isRead: true)
        }
    }

    var filteredBookmarks: [BookmarkListItem] {
        let items = bookmarkStore?.items ?? []
        switch selectedSidebarItem {
        case .inbox:
            // Unread + items marked read during this Inbox visit (leave only on next enter).
            return items.filter { item in
                !item.isRead || inboxSessionRetainedIDs.contains(item.tweetID)
            }
        case .favorites:
            return items.filter(\.isFavorite)
        case .important:
            return items.filter { $0.importance == .high }
        case .archive:
            return items.filter(\.isArchived)
        case .uncategorized:
            return items.filter { $0.folderID == nil }
        case .folder(let folderID):
            return items.filter { $0.folderID == folderID }
        case .tags, .settings:
            return items
        }
    }

    func reloadBookmarks() async {
        do {
            try await bookmarkStore?.reload(searchText: searchText)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    func configureGrokClient() async {
        let store = KeychainStore.shared
        let webSession = try? XWebSessionStore.load()
        await grokClient.configure(
            .init(
                mode: settings.grokAccessMode,
                model: settings.grokModel,
                outputLanguage: settings.aiOutputLanguage,
                isXConnected: connectionStatus.isXConnected,
                apiKey: try? store.load(.grokAPIKey),
                xAccessToken: try? store.load(.xAccessToken),
                webSession: webSession,
                xUsername: try? store.load(.xUsername)
            )
        )
    }

    func enrichBookmark(text: String, authorUsername: String?) async throws -> GrokEnrichment {
        await configureGrokClient()
        return try await grokClient.enrich(tweetText: text, authorUsername: authorUsername)
    }
}

enum SidebarItem: Hashable, Identifiable {
    case inbox
    case favorites
    case important
    case archive
    case uncategorized
    case folder(String)
    case tags
    case settings

    var id: String {
        switch self {
        case .inbox: "inbox"
        case .favorites: "favorites"
        case .important: "important"
        case .archive: "archive"
        case .uncategorized: "uncategorized"
        case .folder(let folderID): "folder:\(folderID)"
        case .tags: "tags"
        case .settings: "settings"
        }
    }

    var titleKey: LocalizedStringResource {
        switch self {
        case .inbox: "sidebar.inbox"
        case .favorites: "sidebar.favorites"
        case .important: "sidebar.important"
        case .archive: "sidebar.archive"
        case .uncategorized: "sidebar.uncategorized"
        case .folder: "sidebar.folders"
        case .tags: "sidebar.tags"
        case .settings: "sidebar.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray.full.fill"
        case .favorites: "star.fill"
        case .important: "exclamationmark.circle.fill"
        case .archive: "archivebox.fill"
        case .uncategorized: "tray"
        case .folder: "folder.fill"
        case .tags: "tag.fill"
        case .settings: "gearshape.fill"
        }
    }

    var showsBookmarkList: Bool {
        switch self {
        case .tags, .settings: false
        default: true
        }
    }
}
