import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Group {
            switch appModel.phase {
            case .launching:
                ProgressView("status.launching")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("status.failedTitle", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("action.retry") {
                        Task { await appModel.bootstrap() }
                    }
                }
            case .ready:
                if appModel.settings.hasCompletedOnboarding {
                    MainSplitView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    OnboardingView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        .task {
            // Debug hook for UI review: `open -a BookmarkX --args -show-settings`.
            if ProcessInfo.processInfo.arguments.contains("-show-settings") {
                try? await Task.sleep(for: .seconds(3))
                openSettings()
            }
        }
        #endif
    }
}
