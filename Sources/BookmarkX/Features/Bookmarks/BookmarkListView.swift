import SwiftUI

struct BookmarkListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pendingDeleteID: String?
    @State private var filterTab: ListFilterTab = .all
    @FocusState private var isSearchFocused: Bool

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
                            appModel.selectedSidebarItem = .settings
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: Binding(
                        get: { model.selectedBookmarkID },
                        set: { appModel.selectBookmark($0) }
                    )) {
                        ForEach(groupedItems(items)) { section in
                            Section(section.title) {
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
    }

    /// Column-3 top chrome: refresh + search + filter, then selection actions.
    private var columnChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(appModel.isSyncing || appModel.isEnriching)
                .help("action.refresh.help")
                .background(Circle().fill(Color.primary.opacity(0.06)))

                searchField

                if showsUnreadStyle {
                    Menu {
                        ForEach(ListFilterTab.allCases) { tab in
                            Button {
                                filterTab = tab
                            } label: {
                                HStack {
                                    Text(tabTitle(tab))
                                    if filterTab == tab {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .help(Text("bookmarks.filter.menu"))
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                }
            }

            HStack(spacing: 12) {
                selectionActionBar
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(listTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let status = statusLine {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("bookmarks.count \(displayedItems.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
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
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                Image(systemName: selected?.importance == .high ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected?.importance == .high ? Color.red : Color.primary.opacity(selected == nil ? 0.35 : 0.85))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .disabled(selected == nil)
            .help(Text("bookmarks.importance"))

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
                .fill(Color.primary.opacity(0.06))
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
            return String(localized: "sync.status.running")
        }
        if appModel.isEnriching {
            return String(localized: "enrichment.status.running")
        }
        return appModel.syncStatusMessage
    }

    private func tabTitle(_ tab: ListFilterTab) -> String {
        switch tab {
        case .all:
            return String(localized: "bookmarks.filter.all")
        case .unread:
            let count = appModel.filteredBookmarks.filter { !$0.isRead }.count
            return String(format: String(localized: "bookmarks.filter.unreadFormat"), locale: .current, count)
        case .others:
            let count = appModel.filteredBookmarks.filter(\.isRead).count
            return String(format: String(localized: "bookmarks.filter.othersFormat"), locale: .current, count)
        }
    }

    private var listTitle: String {
        switch appModel.selectedSidebarItem {
        case .folder(let folderID):
            return appModel.bookmarkStore?.folders.first(where: { $0.id == folderID })?.name
                ?? String(localized: "sidebar.folders")
        default:
            return String(localized: appModel.selectedSidebarItem.titleKey)
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
}

private struct BookmarkRowView: View {
    let item: BookmarkListItem
    var showsUnreadStyle: Bool = true

    private var appearsUnread: Bool {
        showsUnreadStyle && !item.isRead
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            authorAvatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.authorName)
                        .font(.subheadline.weight(appearsUnread ? .bold : .medium))
                        .lineLimit(1)
                    Text("@\(item.authorUsername)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    importanceGlyph
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(displayTitle)
                    .font(.body.weight(appearsUnread ? .semibold : .regular))
                    .lineLimit(1)

                Text(snippet)
                    .font(.subheadline)
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
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if item.mediaCount > 0 {
                        Label("\(item.mediaCount)", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(appearsUnread ? 1 : 0.88)
    }

    private var authorAvatar: some View {
        Group {
            if let urlString = item.authorProfileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var avatarFallback: some View {
        ZStack {
            Color.accentColor.opacity(0.18)
            Text(String(item.authorName.prefix(1)).uppercased())
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var importanceGlyph: some View {
        switch item.importance {
        case .high:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
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

    private var relativeTime: String {
        item.postedAt.formatted(.relative(presentation: .named))
    }
}
