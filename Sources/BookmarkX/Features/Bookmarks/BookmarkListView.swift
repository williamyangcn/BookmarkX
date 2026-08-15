import SwiftUI

struct BookmarkListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openSettings) private var openSettings
    @State private var pendingDeleteID: String?
    @State private var filterTab: ListFilterTab = .all
    @FocusState private var isSearchFocused: Bool
    @State private var newFolderDraft = ""
    @State private var showNewFolderAlert = false
    @State private var folderAlertTweetID: String?
    @State private var newTagDraft = ""
    @State private var showNewTagAlert = false
    @State private var tagAlertTweetID: String?

    private enum ListFilterTab: String, CaseIterable, Identifiable {
        case all
        case unread
        case others

        var id: String { rawValue }

        var titleKey: LocalizedStringResource {
            switch self {
            case .all: "bookmarks.filter.all"
            case .unread: "bookmarks.filter.unread"
            case .others: "bookmarks.filter.others"
            }
        }
    }

    var body: some View {
        @Bindable var model = appModel
        let items = displayedItems

        VStack(spacing: 0) {
            columnChrome
            Divider()

            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("bookmarks.emptyTitle", systemImage: "bookmark")
                    } description: {
                        Text("bookmarks.emptyDescription")
                    } actions: {
                        Button("onboarding.openSettings") {
                            openSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: Binding(
                        get: { model.selectedBookmarkID },
                        set: { appModel.selectBookmark($0) }
                    )) {
                        ForEach(groupedItems(items)) { section in
                            Section {
                                ForEach(section.items) { item in
                                    BookmarkRowView(
                                        item: item,
                                        showsUnreadStyle: showsUnreadStyle
                                    )
                                    .tag(item.id)
                                    .contextMenu {
                                        bookmarkContextMenu(for: item)
                                    }
                                }
                            } header: {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "bookmarks.delete.title",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("bookmarks.delete.localOnly", role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await appModel.deleteBookmark(tweetID: id, alsoFromX: false) }
            }
            Button("bookmarks.delete.localAndX", role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await appModel.deleteBookmark(tweetID: id, alsoFromX: true) }
            }
            Button("action.cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text("bookmarks.delete.message")
        }
        .alert("folders.newSection", isPresented: $showNewFolderAlert) {
            TextField("folders.newPlaceholder", text: $newFolderDraft)
            Button("folders.create") {
                let name = newFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let tweetID = folderAlertTweetID
                newFolderDraft = ""
                folderAlertTweetID = nil
                guard !name.isEmpty else { return }
                Task { await appModel.createFolder(named: name, movingTweetID: tweetID) }
            }
            Button("action.cancel", role: .cancel) {
                folderAlertTweetID = nil
            }
        }
        .alert("tags.add", isPresented: $showNewTagAlert) {
            TextField("tags.addPlaceholder", text: $newTagDraft)
            Button("tags.add") {
                let name = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let tweetID = tagAlertTweetID
                newTagDraft = ""
                tagAlertTweetID = nil
                guard !name.isEmpty, let tweetID else { return }
                Task { await appModel.addTag(tweetID: tweetID, named: name) }
            }
            Button("action.cancel", role: .cancel) {
                tagAlertTweetID = nil
            }
        }
    }

    /// Column-2 chrome: title + refresh, search, then filter + selection actions.
    private var columnChrome: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(listTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)

                if let status = statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("bookmarks.count \(displayedItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await appModel.refreshBookmarks() }
                } label: {
                    Group {
                        if appModel.isSyncing || appModel.isEnriching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(appModel.isSyncing || appModel.isEnriching)
                .help("action.refresh.help")
                .background(Circle().fill(Color.primary.opacity(0.06)))
            }

            searchField

            HStack(spacing: 12) {
                if showsUnreadStyle {
                    Picker(selection: $filterTab) {
                        ForEach(ListFilterTab.allCases) { tab in
                            Text(tab.titleKey).tag(tab)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                Spacer(minLength: 8)

                selectionActionBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(
                "search.prompt",
                text: Binding(
                    get: { appModel.searchText },
                    set: { appModel.searchText = $0 }
                )
            )
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            if !appModel.searchText.isEmpty {
                Button {
                    appModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var selectionActionBar: some View {
        let selected = selectedItem
        HStack(spacing: 0) {
            actionIcon(
                systemImage: selected?.isRead == true ? "envelope.badge" : "envelope.open",
                help: selected?.isRead == true ? "bookmarks.markUnread" : "bookmarks.markRead",
                disabled: selected == nil
            ) {
                guard let selected else { return }
                Task { await appModel.setRead(tweetID: selected.tweetID, isRead: !selected.isRead) }
            }

            pillDivider

            actionIcon(
                systemImage: selected?.isFavorite == true ? "star.fill" : "star",
                tint: selected?.isFavorite == true ? .yellow : nil,
                help: selected?.isFavorite == true ? "bookmarks.unfavorite" : "bookmarks.favorite",
                disabled: selected == nil
            ) {
                guard let selected else { return }
                Task { await appModel.setFavorite(tweetID: selected.tweetID, isFavorite: !selected.isFavorite) }
            }

            pillDivider

            Menu {
                ForEach(BookmarkImportance.allCases) { level in
                    Button {
                        guard let selected else { return }
                        Task { await appModel.setImportance(tweetID: selected.tweetID, importance: level) }
                    } label: {
                        Label(level.titleKey, systemImage: level.systemImage)
                    }
                    .disabled(selected == nil)
                }
            } label: {
                Image(systemName: selected?.importance == .high ? "flag.fill" : "flag")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected?.importance == .high ? Color.red : Color.primary.opacity(selected == nil ? 0.35 : 0.85))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(selected == nil)
            .help(Text("bookmarks.importance"))

            pillDivider

            Menu {
                moveToFolderMenu(for: selected)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(selected == nil ? 0.35 : 0.85))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(selected == nil)
            .help(Text("bookmarks.moveToFolder"))

            pillDivider

            Menu {
                tagMenu(for: selected)
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(selected == nil ? 0.35 : 0.85))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(selected == nil)
            .help(Text("tags.add"))

            pillDivider

            actionIcon(
                systemImage: "archivebox",
                help: selected?.isArchived == true ? "bookmarks.unarchive" : "bookmarks.archive",
                disabled: selected == nil
            ) {
                guard let selected else { return }
                Task { await appModel.setArchived(tweetID: selected.tweetID, isArchived: !selected.isArchived) }
            }

            pillDivider

            actionIcon(
                systemImage: "trash",
                tint: .red,
                help: "bookmarks.delete.local",
                disabled: selected == nil
            ) {
                guard let selected else { return }
                pendingDeleteID = selected.id
            }
        }
        .padding(.horizontal, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }

    private func actionIcon(
        systemImage: String,
        tint: Color? = nil,
        help: LocalizedStringResource,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Color.primary.opacity(disabled ? 0.35 : 0.85))
                .frame(width: 30, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(Text(help))
    }

    /// Archive is a done pile — never emphasize unread there.
    private var showsUnreadStyle: Bool {
        appModel.selectedSidebarItem != .archive
    }

    private var selectedItem: BookmarkListItem? {
        guard let id = appModel.selectedBookmarkID else { return nil }
        return appModel.bookmarkStore?.items.first(where: { $0.id == id })
    }

    private var statusLine: String? {
        if appModel.isSyncing {
            return AppLocalization.text("sync.status.running")
        }
        if appModel.isEnriching {
            return AppLocalization.text("enrichment.status.running")
        }
        return appModel.syncStatusMessage
    }

    private var listTitle: String {
        switch appModel.selectedSidebarItem {
        case .folder(let folderID):
            return appModel.bookmarkStore?.folders.first(where: { $0.id == folderID })?.name
                ?? AppLocalization.text("sidebar.folders")
        default:
            return AppLocalization.text(resource: appModel.selectedSidebarItem.titleKey)
        }
    }

    private var displayedItems: [BookmarkListItem] {
        let base = appModel.filteredBookmarks.sorted { $0.postedAt > $1.postedAt }
        guard showsUnreadStyle else { return base }
        switch filterTab {
        case .all: return base
        case .unread: return base.filter { !$0.isRead }
        case .others: return base.filter(\.isRead)
        }
    }

    private struct TimeSection: Identifiable {
        var group: BookmarkTimeGroup
        var items: [BookmarkListItem]
        var id: BookmarkTimeGroup { group }
        var title: String { group.title }
    }

    private func groupedItems(_ items: [BookmarkListItem]) -> [TimeSection] {
        var buckets: [BookmarkTimeGroup: [BookmarkListItem]] = [:]
        for item in items {
            let group = BookmarkTimeGroup.group(for: item.postedAt)
            buckets[group, default: []].append(item)
        }

        return buckets.keys.sorted().map { group in
            TimeSection(
                group: group,
                items: (buckets[group] ?? []).sorted { $0.postedAt > $1.postedAt }
            )
        }
    }

    @ViewBuilder
    private func bookmarkContextMenu(for item: BookmarkListItem) -> some View {
        Button {
            Task { await appModel.setRead(tweetID: item.tweetID, isRead: !item.isRead) }
        } label: {
            Label(
                item.isRead ? "bookmarks.markUnread" : "bookmarks.markRead",
                systemImage: item.isRead ? "envelope.badge" : "envelope.open"
            )
        }

        Button {
            Task { await appModel.setFavorite(tweetID: item.tweetID, isFavorite: !item.isFavorite) }
        } label: {
            Label(
                item.isFavorite ? "bookmarks.unfavorite" : "bookmarks.favorite",
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }

        Menu("bookmarks.importance") {
            ForEach(BookmarkImportance.allCases) { level in
                Button {
                    Task { await appModel.setImportance(tweetID: item.tweetID, importance: level) }
                } label: {
                    Label(level.titleKey, systemImage: level.systemImage)
                }
            }
        }

        Menu("bookmarks.moveToFolder") {
            moveToFolderMenu(for: item)
        }

        Menu("sidebar.tags") {
            tagMenu(for: item)
        }

        Button {
            Task { await appModel.setArchived(tweetID: item.tweetID, isArchived: !item.isArchived) }
        } label: {
            Label(
                item.isArchived ? "bookmarks.unarchive" : "bookmarks.archive",
                systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Divider()

        Button("bookmarks.delete.local", role: .destructive) {
            pendingDeleteID = item.id
        }
    }

    @ViewBuilder
    private func moveToFolderMenu(for item: BookmarkListItem?) -> some View {
        let folders = appModel.bookmarkStore?.folders ?? []

        Button {
            guard let item else { return }
            Task { await appModel.moveBookmark(tweetID: item.tweetID, toFolderID: nil) }
        } label: {
            HStack {
                Text("sidebar.uncategorized")
                if item?.folderID == nil {
                    Image(systemName: "checkmark")
                }
            }
        }
        .disabled(item == nil)

        if !folders.isEmpty {
            Divider()
            ForEach(folders) { folder in
                Button {
                    guard let item else { return }
                    Task { await appModel.moveBookmark(tweetID: item.tweetID, toFolderID: folder.id) }
                } label: {
                    HStack {
                        Text(folder.name)
                        if item?.folderID == folder.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(item == nil)
            }
        }

        Divider()
        Button("folders.newSection") {
            folderAlertTweetID = item?.tweetID
            newFolderDraft = ""
            showNewFolderAlert = true
        }
        .disabled(item == nil)
    }

    @ViewBuilder
    private func tagMenu(for item: BookmarkListItem?) -> some View {
        let existing = appModel.bookmarkStore?.tags ?? []
        let attached = Set(item?.tags.map { $0.lowercased() } ?? [])

        if !existing.isEmpty {
            ForEach(existing) { tag in
                Button {
                    guard let item else { return }
                    if attached.contains(tag.name.lowercased()) {
                        Task { await appModel.removeTag(tweetID: item.tweetID, named: tag.name) }
                    } else {
                        Task { await appModel.addTag(tweetID: item.tweetID, named: tag.name) }
                    }
                } label: {
                    HStack {
                        Text(tag.name)
                        if attached.contains(tag.name.lowercased()) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(item == nil)
            }
            Divider()
        }

        Button("tags.add") {
            tagAlertTweetID = item?.tweetID
            newTagDraft = ""
            showNewTagAlert = true
        }
        .disabled(item == nil)
    }
}

private struct BookmarkRowView: View {
    let item: BookmarkListItem
    var showsUnreadStyle: Bool = true

    private var appearsUnread: Bool {
        showsUnreadStyle && !item.isRead
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadDot
            authorAvatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.authorName)
                        .font(.subheadline.weight(appearsUnread ? .bold : .medium))
                        .lineLimit(1)
                    Text("@\(item.authorUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    importanceGlyph
                    Text(AppLocalization.relativeDate(item.postedAt))
                        .font(.caption2.weight(appearsUnread ? .semibold : .regular))
                        .foregroundStyle(appearsUnread ? Color.accentColor : Color.secondary)
                }

                Text(displayTitle)
                    .font(.callout.weight(appearsUnread ? .semibold : .regular))
                    .lineLimit(1)

                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if let category = item.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if item.mediaCount > 0 {
                        Label("\(item.mediaCount)", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    /// Leading accent dot, mail-style. Keeps a fixed gutter so rows stay aligned.
    private var unreadDot: some View {
        Circle()
            .fill(appearsUnread ? Color.accentColor : Color.clear)
            .frame(width: 7, height: 7)
            .padding(.top, 5)
    }

    private var authorAvatar: some View {
        CachedAsyncImage(
            url: item.authorProfileImageURL.flatMap(URL.init(string:)),
            width: 36,
            height: 36,
            fallback: { AnyView(avatarFallback) }
        )
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(item.authorName.prefix(1)).uppercased())
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var importanceGlyph: some View {
        switch item.importance {
        case .high:
            Image(systemName: "flag.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .help(Text("importance.high"))
        case .low:
            Image(systemName: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(Text("importance.low"))
        case .normal:
            EmptyView()
        }
    }

    private var displayTitle: String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           !LocalBookmarkClassifier.isWeakTitle(title) {
            return title
        }
        return LocalBookmarkClassifier.makeTitle(
            text: item.text,
            authorUsername: item.authorUsername,
            hasMedia: item.mediaCount > 0
        )
    }

    private var snippet: String {
        if let summary = item.summary, !summary.isEmpty {
            return summary
        }
        return item.text
    }
}
