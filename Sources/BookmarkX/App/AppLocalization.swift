import Foundation

/// App-wide UI localization. SwiftUI `Text("key")` follows `.environment(\.locale)`,
/// but `String(localized:)` defaults to the system locale — keep them in sync here.
enum AppLocalization {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var locale: Locale = .autoupdatingCurrent
    }

    private static let box = Box()

    static var locale: Locale {
        get {
            box.lock.lock()
            defer { box.lock.unlock() }
            return box.locale
        }
        set {
            box.lock.lock()
            box.locale = newValue
            box.lock.unlock()
        }
    }

    static func sync(from language: AppLanguage) {
        locale = language.locale
    }

    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }

    static func text(resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let template = text(key)
        return String(format: template, locale: locale, arguments: arguments)
    }

    static func relativeDate(_ date: Date) -> String {
        date.formatted(
            Date.RelativeFormatStyle(
                presentation: .named,
                unitsStyle: .abbreviated,
                locale: locale,
                calendar: locale.calendar,
                capitalizationContext: .standalone
            )
        )
    }
}
