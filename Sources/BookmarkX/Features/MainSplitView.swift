import SwiftUI

struct MainSplitView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HStack(spacing: 0) {
                ShortcutRailView()
                    .frame(width: 68)
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
        VStack(spacing: 8) {
            ForEach(shortcuts) { item in
                railButton(item)
            }

            Spacer(minLength: 0)

            railButton(.settings) {
                openSettings()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func railButton(_ item: SidebarItem, action: (() -> Void)? = nil) -> some View {
        let selected = isSelected(item)
        return Button {
            if let action {
                action()
            } else {
                appModel.selectSidebarItem(item)
            }
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                .frame(width: 44, height: 44)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item == .inbox, let count = appModel.bookmarkStore?.unreadCount, count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(selected ? Color.primary.opacity(0.55) : Color.accentColor))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(Text(item.titleKey))
        .accessibilityLabel(Text(item.titleKey))
    }

    private func isSelected(_ item: SidebarItem) -> Bool {
        appModel.selectedSidebarItem == item
    }
}

private struct MailFolderSidebar: View {
    @Environment(AppModel.self) private var appModel
    @State private var newFolderName = ""
    @FocusState private var isNewFolderFieldFocused: Bool

    var body: some View {
        let store = appModel.bookmarkStore
        let folders = store?.folders ?? []

        List(selection: Binding(
            get: { appModel.selectedSidebarItem },
            set: { appModel.selectSidebarItem($0) }
        )) {
            Section("sidebar.mailboxes") {
                mailboxRow(.inbox, count: store?.unreadCount ?? 0, color: .accentColor, prominent: true)
                mailboxRow(.favorites, count: store?.favoriteCount ?? 0, color: .yellow)
                mailboxRow(.important, count: store?.importantCount ?? 0, color: .red)
                mailboxRow(.archive, count: archiveCount, color: .secondary)
                mailboxRow(.uncategorized, count: uncategorizedCount, color: .gray)
            }

            Section("sidebar.folders") {
                ForEach(folders) { folder in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: folder.colorHex) ?? .accentColor)
                            .frame(width: 8, height: 8)
                        Text(folder.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let count = store?.folderUnreadCounts[folder.id], count > 0 {
                            CountLabel(count: count)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(SidebarItem.folder(folder.id))
                }

                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                    TextField("folders.newPlaceholder", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNewFolderFieldFocused)
                        .onSubmit(createFolder)
                    Button("folders.create", action: createFolder)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newFolderName = ""
        Task { await appModel.createFolder(named: name) }
    }

    private func mailboxRow(
        _ item: SidebarItem,
        count: Int,
        color: Color,
        prominent: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(item.titleKey)
            Spacer(minLength: 0)
            CountLabel(count: count, prominent: prominent)
        }
        .padding(.vertical, 2)
        .tag(item)
    }

    private var archiveCount: Int {
        appModel.bookmarkStore?.items.filter(\.isArchived).count ?? 0
    }

    private var uncategorizedCount: Int {
        appModel.bookmarkStore?.items.filter { $0.folderID == nil }.count ?? 0
    }
}

/// Sidebar counts: a quiet number for totals, an accent pill for unread.
private struct CountLabel: View {
    let count: Int
    var prominent: Bool = false

    var body: some View {
        if count > 0 {
            if prominent {
                Text(count, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            } else {
                Text(count, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
