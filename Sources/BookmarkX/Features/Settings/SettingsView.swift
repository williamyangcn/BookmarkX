import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var grokAPIKeyDraft = ""
    @State private var statusMessage: String?
    @State private var isSigningIn = false
    @State private var isTestingGrok = false
    @State private var showAdvancedGrok = false
    @State private var showEmbeddedLogin = false
    @State private var selectedPane: SettingsPane = .account
    @FocusState private var isClientIDFieldFocused: Bool

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case account
        case grok
        case sync
        case language
        case data

        var id: String { rawValue }

        var titleKey: LocalizedStringResource {
            switch self {
            case .account: "auth.xLogin"
            case .grok: "settings.grok"
            case .sync: "settings.sync"
            case .language: "settings.language"
            case .data: "settings.data"
            }
        }

        var systemImage: String {
            switch self {
            case .account: "person.crop.circle"
            case .grok: "sparkles"
            case .sync: "arrow.triangle.2.circlepath"
            case .language: "globe"
            case .data: "externaldrive"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label {
                    Text(pane.titleKey)
                } icon: {
                    Image(systemName: pane.systemImage)
                }
                .padding(.vertical, 2)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 180)
        } detail: {
            Group {
                switch selectedPane {
                case .account: accountPane
                case .grok: grokPane
                case .sync: syncPane
                case .language: languagePane
                case .data: dataPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            grokAPIKeyDraft = (try? KeychainStore.shared.load(.grokAPIKey)) ?? ""
            refreshGrokState()
        }
        .sheet(isPresented: $showEmbeddedLogin) {
            XWebLoginSheet { result in
                Task { await handleEmbeddedLogin(result) }
            }
        }
    }

    // MARK: - X account

    private var accountPane: some View {
        @Bindable var settings = appModel.settings

        return Form {
            Section {
                if appModel.connectionStatus.isXConnected {
                    HStack(spacing: 12) {
                        xMarkBadge
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appModel.connectionStatus.xUsername.map { "@\($0)" }
                                ?? AppLocalization.text("status.xConnected"))
                                .font(.headline)
                            Text("status.xConnected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("settings.disconnectX", role: .destructive) {
                            appModel.signOutX()
                            statusMessage = AppLocalization.text("settings.xDisconnected")
                        }
                    }
                    .padding(.vertical, 4)

                    Text("auth.signedInBenefits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            xMarkBadge
                            VStack(alignment: .leading, spacing: 2) {
                                Text("auth.signInWithX.headline")
                                    .font(.headline)
                                Text(hasClientID ? "auth.browserLogin.caption" : "auth.signInWithX.caption")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        SignInWithXButton(isLoading: isSigningIn) {
                            Task { await signIn() }
                        }

                        if !hasClientID {
                            clientIDCard(settings: $settings)
                        }

                        Button("auth.embeddedLogin") {
                            showEmbeddedLogin = true
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("auth.xLogin")
            } footer: {
                if !appModel.connectionStatus.isXConnected && !hasClientID {
                    Text("auth.clientID.highlight")
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var xMarkBadge: some View {
        Image("XLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// One-time Client ID setup, inline — the browser OAuth path needs it.
    private func clientIDCard(settings: Bindable<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("auth.clientID.onceHelp")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("settings.xClientID", text: settings.xClientID)
                .textFieldStyle(.roundedBorder)
                .focused($isClientIDFieldFocused)
            LabeledContent("settings.xCallbackURL") {
                Text(XOAuthService.callbackURL)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            Link("settings.openDeveloperPortal", destination: URL(string: "https://developer.x.com/en/portal/dashboard")!)
                .font(.caption)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Grok

    private var grokPane: some View {
        @Bindable var settings = appModel.settings

        return Form {
            Section {
                Picker("settings.grokAccessMode", selection: $settings.grokAccessMode) {
                    ForEach(GrokAccessMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .onChange(of: settings.grokAccessMode) { _, _ in
                    refreshGrokState()
                }

                Text(settings.grokAccessMode.detailKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("settings.grokStatus") {
                    Text(appModel.connectionStatus.grokStatusKey)
                        .foregroundStyle(appModel.connectionStatus.isGrokConfigured ? .primary : .secondary)
                }

                Button {
                    Task { await testGrok() }
                } label: {
                    if isTestingGrok {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("settings.testingGrok")
                        }
                    } else {
                        Text("settings.testGrok")
                    }
                }
                .disabled(isTestingGrok || !appModel.connectionStatus.isGrokConfigured)
            } footer: {
                Text("settings.grokFooter.premiumFirst")
            }

            Section("settings.model") {
                TextField("settings.grokModel", text: $settings.grokModel)
            }

            Section {
                DisclosureGroup("auth.advancedOptional", isExpanded: $showAdvancedGrok) {
                    SecureField("settings.grokAPIKey", text: $grokAPIKeyDraft)
                    Button("settings.saveGrokKey") {
                        saveGrokKey()
                    }
                    .disabled(grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Link("settings.openXAIConsole", destination: URL(string: "https://console.x.ai/")!)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sync

    private var syncPane: some View {
        @Bindable var settings = appModel.settings

        return Form {
            Section {
                Stepper(value: $settings.syncBatchSize, in: 1...100) {
                    Text(
                        AppLocalization.format("settings.syncBatchSizeFormat", settings.syncBatchSize)
                    )
                }
                Toggle("settings.syncSkipAlreadySynced", isOn: $settings.syncSkipAlreadySynced)
                Toggle("settings.syncDeleteFromXAfterSync", isOn: $settings.syncDeleteFromXAfterSync)
            }

            Section {
                Button {
                    Task { await syncNow() }
                } label: {
                    if appModel.isSyncing {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("sync.status.running")
                        }
                    } else {
                        Text("settings.syncNow")
                    }
                }
                .disabled(appModel.isSyncing || !appModel.connectionStatus.isXConnected)

                Button {
                    Task {
                        await appModel.reclassifyAllBookmarks()
                        statusMessage = appModel.syncStatusMessage
                    }
                } label: {
                    if appModel.isEnriching {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("enrichment.status.running")
                        }
                    } else {
                        Text("settings.reclassifyAll")
                    }
                }
                .disabled(appModel.isEnriching || appModel.isSyncing)
            } footer: {
                Text("settings.sync.footer")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Language

    private var languagePane: some View {
        @Bindable var settings = appModel.settings

        return Form {
            Section("settings.language") {
                Picker("settings.interfaceLanguage", selection: $settings.interfaceLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.titleKey).tag(language)
                    }
                }
                Picker("settings.aiOutputLanguage", selection: $settings.aiOutputLanguage) {
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                        Text(language.titleKey).tag(language)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var dataPane: some View {
        Form {
            Section("settings.data") {
                LabeledContent("settings.localDatabase") {
                    Text("settings.localDatabaseValue")
                }
                Button("settings.clearCredentials", role: .destructive) {
                    appModel.clearAllCredentials()
                    grokAPIKeyDraft = ""
                    statusMessage = AppLocalization.text("settings.credentialsCleared")
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private var hasClientID: Bool {
        !appModel.settings.xClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshGrokState() {
        appModel.connectionStatus.refresh(from: appModel.settings)
        Task { await appModel.configureGrokClient() }
    }

    private func saveGrokKey() {
        let key = grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.shared.save(key, for: .grokAPIKey)
            refreshGrokState()
            statusMessage = AppLocalization.text("settings.grokSaved")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func handleEmbeddedLogin(_ result: Result<XWebSession, Error>) async {
        switch result {
        case .success(let session):
            switch await appModel.completeWebSignIn(session) {
            case .signedIn(let username):
                statusMessage = AppLocalization.format("settings.xConnectedAsFormat", username)
            case .cancelled:
                statusMessage = AppLocalization.text("oauth.error.cancelled")
            case .missingClientID:
                statusMessage = AppLocalization.text("auth.clientID.required")
            case .failed(let message):
                statusMessage = message
            }
        case .failure(let error):
            if let oauthError = error as? XOAuthError, oauthError == .cancelled {
                statusMessage = AppLocalization.text("oauth.error.cancelled")
            } else {
                statusMessage = error.localizedDescription
            }
        }
    }

    /// Default path is in-app web login (no Developer Client ID). Browser OAuth
    /// is used when a Client ID is already configured.
    private func signIn() async {
        if !hasClientID {
            statusMessage = nil
            showEmbeddedLogin = true
            return
        }

        isSigningIn = true
        statusMessage = AppLocalization.text("auth.browserLogin.opening")
        defer { isSigningIn = false }

        switch await appModel.signInWithXInBrowser() {
        case .signedIn(let username):
            statusMessage = AppLocalization.format("settings.xConnectedAsFormat", username)
        case .cancelled:
            statusMessage = AppLocalization.text("oauth.error.cancelled")
        case .missingClientID:
            isClientIDFieldFocused = true
            showEmbeddedLogin = true
            statusMessage = AppLocalization.text("auth.clientID.required")
        case .failed(let message):
            statusMessage = message
        }
    }

    private func syncNow() async {
        await appModel.syncBookmarks()
        statusMessage = appModel.syncStatusMessage
    }

    private func testGrok() async {
        isTestingGrok = true
        defer { isTestingGrok = false }
        do {
            let result = try await appModel.enrichBookmark(
                text: "BookmarkX helps organize X bookmarks with Grok summaries, categories, and tags.",
                authorUsername: "bookmarkx"
            )
            statusMessage = AppLocalization.format("settings.grokTestSuccessFormat", result.provider.rawValue,
                result.category,
                result.summary
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
