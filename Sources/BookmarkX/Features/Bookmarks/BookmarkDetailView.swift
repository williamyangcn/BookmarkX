import AppKit
import SwiftUI
import WebKit

struct BookmarkDetailView: View {
    @Environment(AppModel.self) private var appModel
    let item: BookmarkListItem

    @State private var noteDraft: String = ""
    @State private var didLoadNote = false
    @State private var showWebPreview = true
    @State private var newTagDraft = ""

    private var postURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = "/\(item.authorUsername)/status/\(item.tweetID)"
        return components.url ?? URL(string: "https://x.com/i/status/\(item.tweetID)")!
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            tagEditorBar
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
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    Button {
                        showWebPreview.toggle()
                    } label: {
                        Image(systemName: showWebPreview ? "doc.plaintext" : "globe")
                            .frame(width: 30, height: 28)
                    }
                    .help(Text(showWebPreview ? "detail.showMetadata" : "detail.showPreview"))

                    detailPillDivider

                    Link(destination: postURL) {
                        Image("XLogo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .frame(width: 30, height: 28)
                    }
                    .help(Text("detail.openOnX"))
                }
                .buttonStyle(.plain)
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

            HStack(spacing: 10) {
                authorAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.authorName)
                        .font(.subheadline.weight(.semibold))
                    Text("@\(item.authorUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var tagEditorBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .semibold))

            WrappingHStack(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.caption)
                        Button {
                            Task { await appModel.removeTag(tweetID: item.tweetID, named: tag) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help(Text("tags.remove"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }

                TextField("tags.addPlaceholder", text: $newTagDraft)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 90, maxWidth: 160)
                    .onSubmit(addDraftTag)
            }

            Button("tags.add", action: addDraftTag)
                .disabled(newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func addDraftTag() {
        let name = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newTagDraft = ""
        Task { await appModel.addTag(tweetID: item.tweetID, named: name) }
    }

    private var detailPillDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
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
                .font(.headline)
                .foregroundStyle(Color.accentColor)
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
}

private struct XPostWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = XWebCookieBridge.previewDataStore
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
        private var pendingURL: URL?
        private var isPreparing = false

        func load(url: URL) {
            pendingURL = url
            guard let webView else { return }
            guard !isPreparing else { return }
            isPreparing = true
            Task { [weak self] in
                guard let self else { return }
                await XWebCookieBridge.applySavedSession(to: webView.configuration.websiteDataStore.httpCookieStore)
                while let target = self.pendingURL {
                    self.pendingURL = nil
                    self.loadedURL = target
                    webView.load(URLRequest(url: target))
                    await Task.yield()
                }
                self.isPreparing = false
                if let queued = self.pendingURL {
                    self.load(url: queued)
                }
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

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: max(maxX, 0), height: y + rowHeight))
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
