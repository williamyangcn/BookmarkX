import AppKit
import SwiftUI
import WebKit

struct XWebLoginSheet: View {
    var onComplete: (Result<XWebSession, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false
    @State private var statusText = AppLocalization.text("auth.session.waiting")
    @State private var canContinue = false
    @State private var pendingSession: XWebSession?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("auth.signInWithX")
                    .font(.headline)
                Spacer()
                Button("action.cancel") {
                    onComplete(.failure(XOAuthError.cancelled))
                    dismiss()
                }
            }
            .padding()

            Divider()

            XLoginWebView(
                isChecking: $isChecking,
                statusText: $statusText,
                canContinue: $canContinue,
                pendingSession: $pendingSession
            ) { result in
                onComplete(result)
                dismiss()
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if canContinue, let pendingSession {
                        Button("auth.session.continue") {
                            onComplete(.success(pendingSession))
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text("auth.session.googleHint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 860, minHeight: 760)
    }
}

private struct XLoginWebView: NSViewRepresentable {
    @Binding var isChecking: Bool
    @Binding var statusText: String
    @Binding var canContinue: Bool
    @Binding var pendingSession: XWebSession?
    var onComplete: (Result<XWebSession, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let config = WKWebViewConfiguration()
        // Share the default store with post preview so Google → X cookies stick.
        config.websiteDataStore = .default()
        config.processPool = context.coordinator.processPool
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = XWebCookieBridge.safariUserAgent
        context.coordinator.webView = webView
        context.coordinator.dataStore = webView.configuration.websiteDataStore

        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        webView.load(URLRequest(url: URL(string: "https://x.com/i/flow/login")!))
        context.coordinator.startPolling()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
        var parent: XLoginWebView
        weak var webView: WKWebView?
        let processPool = WKProcessPool()
        var dataStore = WKWebsiteDataStore.default()

        private var didFinish = false
        private var pollTask: Task<Void, Never>?
        private var popupWindow: NSWindow?
        private weak var popupWebView: WKWebView?

        init(parent: XLoginWebView) {
            self.parent = parent
        }

        deinit {
            pollTask?.cancel()
        }

        /// Google / Apple must stay in OUR cookie jar. Loading them in the system
        /// browser or a detached store breaks the redirect back to x.com.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let url = navigationAction.request.url

            // Prefer same-window navigation for Google / Apple SSO — most reliable.
            if let url, isExternalSSOHost(url) {
                parent.statusText = AppLocalization.text("auth.session.finishGoogle")
                self.webView?.load(URLRequest(url: url))
                return nil
            }

            // Reuse an existing OAuth popup if X opens about:blank first.
            if let popupWebView {
                if let url, url.absoluteString != "about:blank" {
                    popupWebView.load(URLRequest(url: url))
                }
                popupWindow?.makeKeyAndOrderFront(nil)
                return popupWebView
            }

            configuration.processPool = processPool
            configuration.websiteDataStore = dataStore
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.customUserAgent = XWebCookieBridge.safariUserAgent
            popupWebView = popup

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 820),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = AppLocalization.text("auth.session.popupTitle")
            window.contentView = popup
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.makeKeyAndOrderFront(nil)
            popupWindow = window

            parent.statusText = AppLocalization.text("auth.session.finishGoogle")
            // Do NOT call popup.load here — WebKit loads navigationAction into the returned view.
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            closePopupIfNeeded(webView)
            Task { await checkCookies(autoComplete: false) }
        }

        func windowWillClose(_ notification: Notification) {
            popupWebView = nil
            popupWindow = nil
            Task { await checkCookies(autoComplete: false) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                if isExternalSSOHost(url) {
                    parent.statusText = AppLocalization.text("auth.session.finishGoogle")
                } else if isXHost(url) {
                    // Returning from Google/Apple into X — keep polling.
                    parent.statusText = AppLocalization.text("auth.session.verifying")
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await softenGoogleEmbeddedWarnings(in: webView)
                await checkCookies(autoComplete: false)
            }

            // Popup finished back on X → close it and land on home in the main view.
            if webView === popupWebView, let url = webView.url, isXHost(url), !isExternalSSOHost(url) {
                closePopupIfNeeded(webView)
                self.webView?.load(URLRequest(url: URL(string: "https://x.com/home")!))
            }

            // Main view returned to X after Google — nudge home for cookie settle.
            if webView === self.webView, let url = webView.url, isXHost(url),
               url.path.contains("/home") || url.path == "/" || url.path.isEmpty {
                Task { await checkCookies(autoComplete: false) }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.statusText = error.localizedDescription
        }

        func startPolling() {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                guard let self else { return }
                for _ in 0..<240 {
                    if Task.isCancelled || didFinish { return }
                    await checkCookies(autoComplete: false)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        private func closePopupIfNeeded(_ webView: WKWebView) {
            guard webView === popupWebView || popupWebView == nil else { return }
            popupWindow?.delegate = nil
            popupWindow?.close()
            popupWindow = nil
            popupWebView = nil
        }

        private func checkCookies(autoComplete: Bool) async {
            guard !didFinish else { return }
            parent.isChecking = true

            let cookies = await dataStore.httpCookieStore.allCookies()
            let auth = cookies.first(where: {
                ($0.domain.contains("x.com") || $0.domain.contains("twitter.com"))
                    && $0.name == "auth_token" && !$0.value.isEmpty
            })?.value
            let ct0 = cookies.first(where: {
                ($0.domain.contains("x.com") || $0.domain.contains("twitter.com"))
                    && $0.name == "ct0" && !$0.value.isEmpty
            })?.value
            let twidUserID = Self.userID(
                fromTwid: cookies.first(where: {
                    ($0.domain.contains("x.com") || $0.domain.contains("twitter.com"))
                        && $0.name == "twid"
                })?.value
            )

            guard let auth, let ct0 else {
                parent.isChecking = false
                parent.canContinue = false
                return
            }

            parent.statusText = AppLocalization.text("auth.session.verifying")
            var session = XWebSession(authToken: auth, ct0: ct0, userID: twidUserID)

            if let verified = try? await XWebSessionClient().verify(session: session) {
                session = verified
            } else if let username = await scrapeUsername() {
                session.username = username
            }

            try? XWebSessionStore.save(session)
            await XWebCookieBridge.apply(
                session: session,
                to: WKWebsiteDataStore.default().httpCookieStore
            )

            parent.pendingSession = session
            parent.canContinue = true
            parent.isChecking = false
            parent.statusText = AppLocalization.text("auth.session.readyToContinue")

            if autoComplete {
                didFinish = true
                if let popupWebView {
                    closePopupIfNeeded(popupWebView)
                } else {
                    popupWindow?.close()
                    popupWindow = nil
                }
                parent.onComplete(.success(session))
            }
        }

        /// Google sometimes shows a soft warning page inside WKWebView; try to continue.
        private func softenGoogleEmbeddedWarnings(in webView: WKWebView) async {
            guard let host = webView.url?.host?.lowercased(),
                  host.contains("accounts.google.")
            else { return }

            let js = """
            (function() {
              const text = document.body ? document.body.innerText : '';
              if (text.includes('may not be secure') || text.includes('不安全') || text.includes('couldn't sign you in') || text.includes('无法登录')) {
                const links = Array.from(document.querySelectorAll('a, button'));
                const cont = links.find(el => /try again|重试|next|下一步|continue|继续/i.test((el.innerText || el.textContent || '').trim()));
                if (cont) { cont.click(); return 'clicked'; }
                return 'blocked';
              }
              return 'ok';
            })();
            """
            if let result = try? await webView.evaluateJavaScript(js) as? String, result == "blocked" {
                parent.statusText = AppLocalization.text("auth.session.googleBlocked")
            }
        }

        private func scrapeUsername() async -> String? {
            guard let webView else { return nil }
            let js = """
            (function() {
              const anchor = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
              if (anchor && anchor.href) {
                const parts = anchor.href.split('/').filter(Boolean);
                return parts[parts.length - 1] || null;
              }
              return null;
            })();
            """
            return try? await webView.evaluateJavaScript(js) as? String
        }

        private func isExternalSSOHost(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            if host.contains("accounts.google.") { return true }
            if host.contains("google.com"), url.path.contains("/o/oauth2") { return true }
            if host.contains("appleid.apple.com") || host.contains("idmsa.apple.com") { return true }
            return false
        }

        private func isXHost(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "x.com"
                || host.hasSuffix(".x.com")
                || host == "twitter.com"
                || host.hasSuffix(".twitter.com")
        }

        private static func userID(fromTwid value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            let decoded = value.removingPercentEncoding ?? value
            if decoded.hasPrefix("u="), decoded.count > 2 {
                return String(decoded.dropFirst(2))
            }
            if let match = decoded.range(of: #"\d{5,}"#, options: .regularExpression) {
                return String(decoded[match])
            }
            return nil
        }
    }
}
