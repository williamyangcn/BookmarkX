import Foundation
import WebKit

/// Seeds WKWebView cookie jars with the saved x.com web session.
enum XWebCookieBridge {
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

    @MainActor
    static func applySavedSession(to cookieStore: WKHTTPCookieStore) async {
        guard let session = try? XWebSessionStore.load() else { return }
        await apply(session: session, to: cookieStore)
    }

    @MainActor
    static func apply(session: XWebSession, to cookieStore: WKHTTPCookieStore) async {
        let domains = [".x.com", ".twitter.com"]
        for domain in domains {
            for cookie in makeCookies(session: session, domain: domain) {
                await cookieStore.setCookie(cookie)
            }
        }
    }

    private static func makeCookies(session: XWebSession, domain: String) -> [HTTPCookie] {
        func cookie(name: String, value: String) -> HTTPCookie? {
            HTTPCookie(properties: [
                .name: name,
                .value: value,
                .path: "/",
                .domain: domain,
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365),
            ])
        }

        var cookies: [HTTPCookie] = []
        if let auth = cookie(name: "auth_token", value: session.authToken) {
            cookies.append(auth)
        }
        if let ct0 = cookie(name: "ct0", value: session.ct0) {
            cookies.append(ct0)
        }
        if let userID = session.userID,
           let twid = cookie(name: "twid", value: "u%3D\(userID)") {
            cookies.append(twid)
        }
        return cookies
    }
}
