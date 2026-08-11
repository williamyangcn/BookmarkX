import AppKit
import SwiftUI
import WebKit

struct BookmarkDetailView: View {
    @Environment(AppModel.self) private var appModel
    let item: BookmarkListItem

    @State private var noteDraft: String = ""
    @State private var didLoadNote = false
    @State private var showDeleteConfirm = false
    @State private var showWebPreview = true

    private var postURL: URL {
        URL(string: "https://x.com/\(item.authorUsername)/status/\(item.tweetID)")!
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if showWebPreview {
                XPostWebView(url: postURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                metadataScroll
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            attachmentsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !didLoadNote {
                noteDraft = item.note ?? ""
                didLoadNote = true
            }
            appModel.scheduleAutoRead(for: item.tweetID)
        }
        .onChange(of: item.tweetID) { _, _ in
            noteDraft = item.note ?? ""
            didLoadNote = true
            showWebPreview = true
            appModel.scheduleAutoRead(for: item.tweetID)
        }
        .confirmationDialog(
            "bookmarks.delete.title",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("bookmarks.delete.localOnly", role: .destructive) {
                Task { await appModel.deleteBookmark(tweetID: item.tweetID, alsoFromX: false) }
            }
            Button("bookmarks.delete.localAndX", role: .destructive) {
                Task { await appModel.deleteBookmark(tweetID: item.tweetID, alsoFromX: true) }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("bookmarks.delete.message")
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Button {
                    showWebPreview.toggle()
                } label: {
                    Label(
                        showWebPreview ? "detail.showMetadata" : "detail.showPreview",
                        systemImage: showWebPreview ? "doc.plaintext" : "globe"
                    )
                }
                .buttonStyle(.bordered)

                Link(destination: postURL) {
                    Label("detail.openOnX", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                authorAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.authorName)
                        .font(.headline)
                    Text("@\(item.authorUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actionButtons
            }
        }
        .padding(16)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                Task { await appModel.setRead(tweetID: item.tweetID, isRead: !item.isRead) }
            } label: {
                Image(systemName: item.isRead ? "envelope.badge" : "envelope.open")
            }
            .help(Text(item.isRead ? "bookmarks.markUnread" : "bookmarks.markRead"))

            Button {
                Task { await appModel.setFavorite(tweetID: item.tweetID, isFavorite: !item.isFavorite) }
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : .primary)
            }
            .help(Text(item.isFavorite ? "bookmarks.unfavorite" : "bookmarks.favorite"))

            Menu {
                ForEach(BookmarkImportance.allCases) { level in
                    Button {
                        Task { await appModel.setImportance(tweetID: item.tweetID, importance: level) }
                    } label: {
                        Label(level.titleKey, systemImage: level.systemImage)
                    }
                }
            } label: {
                Image(systemName: "exclamationmark.circle")
            }
            .help(Text("bookmarks.importance"))

            Button {
                Task { await appModel.setArchived(tweetID: item.tweetID, isArchived: !item.isArchived) }
            } label: {
                Image(systemName: "archivebox")
            }
            .help(Text(item.isArchived ? "bookmarks.unarchive" : "bookmarks.archive"))

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .help(Text("bookmarks.delete.local"))
        }
        .buttonStyle(.borderless)
    }

    private var metadataScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)

                if let summary = item.summary, !summary.isEmpty {
                    GroupBox("detail.summary") {
                        Text(summary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let category = item.category, !category.isEmpty {
                    LabeledContent("detail.category") {
                        Text(category)
                    }
                }

                if !item.tags.isEmpty {
                    LabeledContent("sidebar.tags") {
                        HStack {
                            ForEach(item.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                GroupBox("detail.note") {
                    TextEditor(text: $noteDraft)
                        .frame(minHeight: 80)
                    Button("action.saveNote") {
                        try? appModel.bookmarkStore?.updateNote(
                            tweetID: item.tweetID,
                            note: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        )
                        Task { await appModel.reloadBookmarks() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                LabeledContent("detail.bookmarkedAt") {
                    Text(item.bookmarkedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var attachmentsBar: some View {
        HStack(spacing: 12) {
            Label("detail.previewFooter", systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(postURL.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            if item.mediaCount > 0 {
                Label("\(item.mediaCount)", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var authorAvatar: some View {
        Group {
            if let urlString = item.authorProfileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var avatarFallback: some View {
        ZStack {
            Color.accentColor.opacity(0.18)
            Text(String(item.authorName.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        }
    }

    private var displayTitle: String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return String(item.text.prefix(80))
    }
}

private struct XPostWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = XWebCookieBridge.safariUserAgent
        context.coordinator.webView = webView
        context.coordinator.load(url: url)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url: url)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private var loadedURL: URL?
        private var isPreparing = false

        func load(url: URL) {
            guard loadedURL != url || webView?.url == nil else { return }
            loadedURL = url
            guard let webView else { return }
            guard !isPreparing else { return }
            isPreparing = true
            Task {
                await XWebCookieBridge.applySavedSession(to: webView.configuration.websiteDataStore.httpCookieStore)
                if loadedURL == url {
                    webView.load(URLRequest(url: url))
                }
                isPreparing = false
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Preview should not trap Google login; open externally and keep reading locally.
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let host = url.host?.lowercased(),
               host.contains("accounts.google.") || host.contains("appleid.apple.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
