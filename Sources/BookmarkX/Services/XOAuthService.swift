import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct XAuthenticatedUser: Sendable {
    let id: String
    let username: String
    let name: String
}

/// Waits for `bookmarkx://oauth/x/callback` from the default browser.
@MainActor
enum XOAuthCallbackHub {
    private static var continuation: CheckedContinuation<URL, Error>?

    static func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { newContinuation in
            if let existing = continuation {
                existing.resume(throwing: XOAuthError.couldNotStartSession)
            }
            continuation = newContinuation
        }
    }

    @discardableResult
    static func handle(url: URL) -> Bool {
        guard url.scheme == "bookmarkx",
              url.host == "oauth" else {
            return false
        }
        guard let pending = continuation else { return false }
        continuation = nil
        pending.resume(returning: url)
        return true
    }

    static func cancel() {
        guard let pending = continuation else { return }
        continuation = nil
        pending.resume(throwing: XOAuthError.cancelled)
    }
}

@MainActor
final class XOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callbackURL = "bookmarkx://oauth/x/callback"

    private var authenticationSession: ASWebAuthenticationSession?

    /// Opens the **default browser** for X login (Google / Apple / passkeys work there).
    func authenticateInDefaultBrowser(clientID: String) async throws -> XAuthenticatedUser {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw XOAuthError.missingClientID
        }

        let verifier = try Self.randomURLSafeString(byteCount: 48)
        let state = try Self.randomURLSafeString(byteCount: 24)
        let challenge = Self.codeChallenge(for: verifier)
        let authorizationURL = try Self.makeAuthorizationURL(
            clientID: trimmedClientID,
            state: state,
            challenge: challenge
        )

        guard NSWorkspace.shared.open(authorizationURL) else {
            throw XOAuthError.couldNotStartSession
        }

        let callback = try await XOAuthCallbackHub.waitForCallback()

        let code = try Self.authorizationCode(from: callback, expectedState: state)
        let token = try await exchangeCode(
            code,
            clientID: trimmedClientID,
            verifier: verifier
        )
        let user = try await fetchCurrentUser(accessToken: token.accessToken)
        try persist(user: user, token: token)
        try KeychainStore.shared.save(XAuthMethod.oauth.rawValue, for: .xAuthMethod)
        return user
    }

    /// System auth session fallback (still better than WKWebView for Google).
    func authenticate(clientID: String) async throws -> XAuthenticatedUser {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw XOAuthError.missingClientID
        }

        let verifier = try Self.randomURLSafeString(byteCount: 48)
        let state = try Self.randomURLSafeString(byteCount: 24)
        let challenge = Self.codeChallenge(for: verifier)
        let authorizationURL = try Self.makeAuthorizationURL(
            clientID: trimmedClientID,
            state: state,
            challenge: challenge
        )

        let callback = try await requestAuthorization(url: authorizationURL)
        let code = try Self.authorizationCode(from: callback, expectedState: state)
        let token = try await exchangeCode(
            code,
            clientID: trimmedClientID,
            verifier: verifier
        )
        let user = try await fetchCurrentUser(accessToken: token.accessToken)
        try persist(user: user, token: token)
        try KeychainStore.shared.save(XAuthMethod.oauth.rawValue, for: .xAuthMethod)
        return user
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }

    private func persist(user: XAuthenticatedUser, token: OAuthTokenResponse) throws {
        let keychain = KeychainStore.shared
        try keychain.save(token.accessToken, for: .xAccessToken)
        if let refreshToken = token.refreshToken {
            try keychain.save(refreshToken, for: .xRefreshToken)
        }
        try keychain.save(user.id, for: .xUserID)
        try keychain.save(user.username, for: .xUsername)
    }

    private func requestAuthorization(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "bookmarkx"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.authenticationSession = nil

                    if let authenticationError = error as? ASWebAuthenticationSessionError,
                       authenticationError.code == .canceledLogin {
                        continuation.resume(throwing: XOAuthError.cancelled)
                        return
                    }

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let callbackURL else {
                        continuation.resume(throwing: XOAuthError.missingCallback)
                        return
                    }

                    continuation.resume(returning: callbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            guard session.start() else {
                authenticationSession = nil
                continuation.resume(throwing: XOAuthError.couldNotStartSession)
                return
            }
        }
    }

    private static func makeAuthorizationURL(
        clientID: String,
        state: String,
        challenge: String
    ) throws -> URL {
        var components = URLComponents(string: "https://x.com/i/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callbackURL),
            URLQueryItem(
                name: "scope",
                value: "tweet.read users.read bookmark.read bookmark.write offline.access"
            ),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components?.url else {
            throw XOAuthError.invalidAuthorizationURL
        }
        return authorizationURL
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        verifier: String
    ) async throws -> OAuthTokenResponse {
        guard let url = URL(string: "https://api.x.com/2/oauth2/token") else {
            throw XOAuthError.invalidTokenURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody([
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL),
            URLQueryItem(name: "code_verifier", value: verifier)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        do {
            return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw XOAuthError.invalidTokenResponse
        }
    }

    private func fetchCurrentUser(accessToken: String) async throws -> XAuthenticatedUser {
        guard let url = URL(string: "https://api.x.com/2/users/me?user.fields=id,name,username") else {
            throw XOAuthError.invalidUserURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        do {
            let envelope = try JSONDecoder().decode(XUserEnvelope.self, from: data)
            return XAuthenticatedUser(
                id: envelope.data.id,
                username: envelope.data.username,
                name: envelope.data.name
            )
        } catch {
            throw XOAuthError.invalidUserResponse
        }
    }

    private static func authorizationCode(
        from callbackURL: URL,
        expectedState: String
    ) throws -> String {
        guard callbackURL.scheme == "bookmarkx",
              callbackURL.host == "oauth",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw XOAuthError.invalidCallback
        }

        // Accept both /x/callback and oauth host path variants.
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        if let error = values["error"] {
            throw XOAuthError.authorizationDenied(
                values["error_description"] ?? error
            )
        }

        guard values["state"] == expectedState else {
            throw XOAuthError.stateMismatch
        }
        guard let code = values["code"], !code.isEmpty else {
            throw XOAuthError.missingAuthorizationCode
        }
        return code
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw XOAuthError.randomGenerationFailed(status)
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formBody(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XOAuthError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(XAPIErrorEnvelope.self, from: data))
                .flatMap { $0.detail ?? $0.title }
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw XOAuthError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

private struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct XUserEnvelope: Decodable, Sendable {
    let data: XUser
}

private struct XUser: Decodable, Sendable {
    let id: String
    let username: String
    let name: String
}

private struct XAPIErrorEnvelope: Decodable, Sendable {
    let title: String?
    let detail: String?
}

enum XOAuthError: LocalizedError, Equatable {
    case missingClientID
    case invalidAuthorizationURL
    case invalidTokenURL
    case invalidUserURL
    case couldNotStartSession
    case cancelled
    case missingCallback
    case invalidCallback
    case authorizationDenied(String)
    case stateMismatch
    case missingAuthorizationCode
    case randomGenerationFailed(OSStatus)
    case invalidHTTPResponse
    case server(statusCode: Int, message: String)
    case invalidTokenResponse
    case invalidUserResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            AppLocalization.text("oauth.error.missingClientID")
        case .invalidAuthorizationURL, .invalidTokenURL, .invalidUserURL:
            AppLocalization.text("oauth.error.invalidURL")
        case .couldNotStartSession:
            AppLocalization.text("oauth.error.couldNotStart")
        case .cancelled:
            AppLocalization.text("oauth.error.cancelled")
        case .missingCallback, .invalidCallback:
            AppLocalization.text("oauth.error.invalidCallback")
        case .authorizationDenied(let message):
            AppLocalization.format("oauth.error.deniedFormat", message
            )
        case .stateMismatch:
            AppLocalization.text("oauth.error.stateMismatch")
        case .missingAuthorizationCode:
            AppLocalization.text("oauth.error.missingCode")
        case .randomGenerationFailed(let status):
            AppLocalization.format("oauth.error.randomFailedFormat", status)
        case .invalidHTTPResponse:
            AppLocalization.text("oauth.error.invalidResponse")
        case .server(let statusCode, let message):
            AppLocalization.format("oauth.error.serverFormat", statusCode, message)
        case .invalidTokenResponse:
            AppLocalization.text("oauth.error.invalidToken")
        case .invalidUserResponse:
            AppLocalization.text("oauth.error.invalidUser")
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
