import Foundation

enum GrokAccessMode: String, CaseIterable, Identifiable, Sendable {
    /// Use Grok quota included with X Premium after connecting an X account.
    case xPremium
    /// Use an official xAI API Key from console.x.ai.
    case apiKey
    /// Prefer X Premium when connected; otherwise fall back to API Key.
    case auto

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .xPremium: "grok.mode.xPremium"
        case .apiKey: "grok.mode.apiKey"
        case .auto: "grok.mode.auto"
        }
    }

    var detailKey: LocalizedStringResource {
        switch self {
        case .xPremium: "grok.mode.xPremium.detail"
        case .apiKey: "grok.mode.apiKey.detail"
        case .auto: "grok.mode.auto.detail"
        }
    }
}
