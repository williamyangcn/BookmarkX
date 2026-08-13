import SwiftUI

@main
struct BookmarkXApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(\.locale, appModel.settings.interfaceLanguage.locale)
                .task {
                    URLCache.shared = URLCache(
                        memoryCapacity: 20 * 1024 * 1024,
                        diskCapacity: 50 * 1024 * 1024
                    )
                    await appModel.bootstrap()
                }
                .onOpenURL { url in
                    _ = appModel.handleIncomingURL(url)
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(appModel)
                .environment(\.locale, appModel.settings.interfaceLanguage.locale)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 620)
        }
    }
}
