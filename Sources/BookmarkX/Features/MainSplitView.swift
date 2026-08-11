import SwiftUI

struct MainSplitView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HStack(spacing: 0) {
                ShortcutRailView()
                    .frame(width: 64)
                    .frame(maxHeight: .infinity)

                Divider()

                MailFolderSidebar()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } content: {
            Group {
                switch appModel.selectedSidebarItem {
                case .tags:
                    TagListView()
                default:
                    BookmarkListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            Group {
                if appModel.selectedSidebarItem.showsBookmarkList,
                   let selectedID = appModel.selectedBookmarkID,
                   let item = appModel.bookmarkStore?.items.first(where: { $0.id == selectedID }) {
                    BookmarkDetailView(item: item)
                } else if appModel.selectedSidebarItem.showsBookmarkList {
                    ContentUnavailableView(
                        "detail.emptyTitle",
                        systemImage: "text.alignleft",
                        description: Text("detail.emptyDescription")
                    )
                } else {
                    ContentUnavailableView(
                        "detail.panelUnavailableTitle",
                        systemImage: "rectangle.split.3x1",
                        description: Text("detail.panelUnavailableDescription")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(min: 420, ideal: 560)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            if !appModel.connectionStatus.isXConnected {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                    Text("auth.banner.title")
                        .font(.callout)
                    Spacer()
                    Button("auth.banner.action") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.12))
            }
        }
        .onAppear {
            // Settings used to live in the list column; keep browsing state if so.
            if appModel.selectedSidebarItem == .settings {
                appModel.selectedSidebarItem = .inbox
            }
        }
        .onChange(of: appModel.searchText) { _, newValue in
            Task {
                try? await appModel.bookmarkStore?.reload(searchText: newValue)
            }
        }
        .onChange(of: appModel.selectedBookmarkID) { _, newValue in
            appModel.scheduleAutoRead(for: newValue)
        }
    }
}

private struct ShortcutRailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openSettings) private var openSettings

    private let shortcuts: [SidebarItem] = [
        .inbox, .favorites, .important, .archive, .tags,
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(shortcuts) { item in
                Button {
                    appModel.selectSidebarItem(item)
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected(item) ? Color.white : Color.primary.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(
                            isSelected(item) ? Color.accentColor : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(Text(item.titleKey))
            }

            Spacer(minLength: 0)

            Button {
                openSettings()
            } label: {
                Image(systemName: SidebarItem.settings.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(Text(SidebarItem.settings.titleKey))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func isSelected(_ item: SidebarItem) -> Bool {
        appModel.selectedSidebarItem == item
    }
}

private struct MailFolderSidebar: View {
    @Environment(AppModel.self) private var appModel
    @State private var newFolderName = ""

    var body: some View {
        let store = appModel.bookmarkStore
        let folders = store?.folders ?? []

        List(selection: Binding(
            get: { appModel.selectedSidebarItem },
            set: { appModel.selectSidebarItem($0) }
        )) {
            Section("sidebar.mailboxes") {
                mailboxRow(.inbox, count: store?.unreadCount ?? 0, color: .orange)
                mailboxRow(.favorites, count: store?.favoriteCount ?? 0, color: .yellow)
                mailboxRow(.important, count: store?.importantCount ?? 0, color: .red)
                mailboxRow(.archive, count: archiveCount, color: .secondary)
                mailboxRow(.uncategorized, count: uncategorizedCount, color: .gray)
            }

            Section {
                ForEach(folders) { folder in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: folder.colorHex) ?? .accentColor)
                            .frame(width: 10, height: 10)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let count = store?.folderUnreadCounts[folder.id], count > 0 {
                            UnreadBadge(count: count, color: Color(hex: folder.colorHex) ?? .accentColor)
                        }
                    }
                    .tag(SidebarItem.folder(folder.id))
                }
            } header: {
                Text("sidebar.folders")
            }

            Section("folders.newSection") {
                HStack {
                    TextField("folders.newPlaceholder", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        try? appModel.bookmarkStore?.createFolder(named: newFolderName)
                        newFolderName = ""
                        Task { await appModel.reloadBookmarks() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mailboxRow(_ item: SidebarItem, count: Int, color: Color) -> some View {
        HStack {
            Label(item.titleKey, systemImage: item.systemImage)
            Spacer(minLength: 0)
            if count > 0 {
                UnreadBadge(count: count, color: color)
            }
        }
        .tag(item)
    }

    private var archiveCount: Int {
        appModel.bookmarkStore?.items.filter(\.isArchived).count ?? 0
    }

    private var uncategorizedCount: Int {
        appModel.bookmarkStore?.items.filter { $0.folderID == nil }.count ?? 0
    }
}

private struct UnreadBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}
