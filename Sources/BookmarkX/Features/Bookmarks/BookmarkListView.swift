import SwiftUI

struct BookmarkListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pendingDeleteID: String?
    @State private var filterTab: ListFilterTab = .all

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
            header
            filterBar
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
                                    BookmarkRowView(item: item) {
                                        pendingDeleteID = item.id
                                    }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(listTitle)
                    .font(.title2.weight(.semibold))
                Text("bookmarks.count \(displayedItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ListFilterTab.allCases) { tab in
                Button {
                    filterTab = tab
                } label: {
                    Text(tabTitle(tab))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            filterTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
    @Environment(AppModel.self) private var appModel
    let item: BookmarkListItem
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            authorAvatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.authorName)
                        .font(.subheadline.weight(item.isRead ? .medium : .bold))
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
                    .font(.body.weight(item.isRead ? .regular : .semibold))
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
                    if isHovered {
                        rowToolbar
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(item.isRead ? 0.88 : 1)
        .onHover { isHovered = $0 }
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

    private var rowToolbar: some View {
        HStack(spacing: 4) {
            Button {
                Task { await appModel.setImportance(tweetID: item.tweetID, importance: item.importance == .high ? .normal : .high) }
            } label: {
                Image(systemName: item.importance == .high ? "exclamationmark.circle.fill" : "exclamationmark.circle")
            }
            .help(Text("bookmarks.importance"))

            Button {
                Task { await appModel.setArchived(tweetID: item.tweetID, isArchived: !item.isArchived) }
            } label: {
                Image(systemName: "archivebox")
            }
            .help(Text(item.isArchived ? "bookmarks.unarchive" : "bookmarks.archive"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help(Text("bookmarks.delete.local"))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var displayTitle: String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        let firstLine = item.text
            .split(whereSeparator: { ".!?。！？\n".contains($0) })
            .first
            .map(String.init) ?? item.text
        return String(firstLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
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
