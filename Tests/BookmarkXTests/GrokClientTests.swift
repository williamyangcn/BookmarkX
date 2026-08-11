import XCTest
@testable import BookmarkX

final class GrokClientTests: XCTestCase {
    func testPreferredProviderForEachMode() async {
        let client = GrokClient()

        await client.configure(
            .init(
                mode: .xPremium,
                model: "grok-4-fast",
                outputLanguage: .simplifiedChinese,
                isXConnected: true,
                apiKey: nil,
                xAccessToken: "token",
                webSession: nil,
                xUsername: "demo"
            )
        )
        let premium = await client.preferredProvider()
        let premiumReady = await client.isConfigured()
        XCTAssertEqual(premium, .xPremium)
        XCTAssertTrue(premiumReady)

        await client.configure(
            .init(
                mode: .apiKey,
                model: "grok-4-fast",
                outputLanguage: .english,
                isXConnected: false,
                apiKey: "xai-key",
                xAccessToken: nil,
                webSession: nil,
                xUsername: nil
            )
        )
        let api = await client.preferredProvider()
        XCTAssertEqual(api, .apiKey)

        await client.configure(
            .init(
                mode: .auto,
                model: "grok-4-fast",
                outputLanguage: .simplifiedChinese,
                isXConnected: false,
                apiKey: "xai-key",
                xAccessToken: nil,
                webSession: nil,
                xUsername: nil
            )
        )
        let autoAPI = await client.preferredProvider()
        XCTAssertEqual(autoAPI, .apiKey)

        await client.configure(
            .init(
                mode: .auto,
                model: "grok-4-fast",
                outputLanguage: .simplifiedChinese,
                isXConnected: true,
                apiKey: "xai-key",
                xAccessToken: "token",
                webSession: nil,
                xUsername: "demo"
            )
        )
        let autoPremium = await client.preferredProvider()
        XCTAssertEqual(autoPremium, .xPremium)
    }

    @MainActor
    func testConnectionStatusForThreeModes() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "BookmarkX.GrokClientTests")!)
        let credentialURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkX-GrokClientTests-\(UUID().uuidString).plist")
        let status = ConnectionStatus(
            credentialStore: KeychainStore(fileURL: credentialURL)
        )

        settings.grokAccessMode = .apiKey
        status.refresh(from: settings)
        XCTAssertFalse(status.isGrokConfigured)

        settings.grokAccessMode = .xPremium
        status.refresh(from: settings)
        XCTAssertEqual(status.grokStatusKey, "status.grokPremiumMissing")

        settings.grokAccessMode = .auto
        status.refresh(from: settings)
        XCTAssertEqual(status.grokStatusKey, "status.grokAutoMissing")
    }
}
