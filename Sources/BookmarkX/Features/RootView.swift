import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

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
    }
}
