import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var grokAPIKeyDraft = ""
    @State private var statusMessage: String?
    @State private var isSigningIn = false
    @State private var isTestingGrok = false
    @State private var showAdvanced = false
    @State private var showEmbeddedLogin = false

    var body: some View {
        @Bindable var settings = appModel.settings

        Form {
            Section {
                if appModel.connectionStatus.isXConnected {
                    LabeledContent("settings.xAccount") {
                        Text(appModel.connectionStatus.xUsername.map { "@\($0)" } ?? AppLocalization.text("status.xConnected"))
                    }

                    Text("auth.signedInBenefits")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("settings.disconnectX", role: .destructive) {
                        appModel.signOutX()
                        statusMessage = AppLocalization.text("settings.xDisconnected")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("auth.signInWithX.headline")
                            .font(.headline)
                        Text(hasClientID ? "auth.browserLogin.caption" : "auth.signInWithX.caption")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SignInWithXButton(isLoading: isSigningIn) {
                            Task { await signIn() }
                        }

                        if hasClientID {
                            Button("auth.embeddedLogin") {
                                showEmbeddedLogin = true
                            }
                            .buttonStyle(.link)
                        } else {
                            Button("auth.browserLogin.needsClientID") {
                                showAdvanced = true
                                statusMessage = AppLocalization.text("auth.clientID.required")
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(.vertical, 4)
                }

                DisclosureGroup("auth.advancedX", isExpanded: $showAdvanced) {
                    Text("auth.clientID.onceHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("settings.xClientID", text: $settings.xClientID)
                    LabeledContent("settings.xCallbackURL") {
                        Text(XOAuthService.callbackURL)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    Link("settings.openDeveloperPortal", destination: URL(string: "https://developer.x.com/en/portal/dashboard")!)
                }
            } header: {
                Text("auth.xLogin")
            } footer: {
                Text(hasClientID ? "auth.xLogin.footer.browser" : "auth.signInWithX.caption")
            }

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
            } header: {
                Text("settings.grok")
            } footer: {
                Text("settings.grokFooter.premiumFirst")
            }

            DisclosureGroup("auth.advancedOptional", isExpanded: $showAdvanced) {
                SecureField("settings.grokAPIKey", text: $grokAPIKeyDraft)
                Button("settings.saveGrokKey") {
                    saveGrokKey()
                }
                .disabled(grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Link("settings.openXAIConsole", destination: URL(string: "https://console.x.ai/")!)
            }

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

            Section("settings.model") {
                TextField("settings.grokModel", text: $settings.grokModel)
            }

            Section {
                Stepper(value: $settings.syncBatchSize, in: 1...100) {
                    Text(
                        AppLocalization.format("settings.syncBatchSizeFormat", settings.syncBatchSize)
                    )
                }
                Toggle("settings.syncSkipAlreadySynced", isOn: $settings.syncSkipAlreadySynced)
                Toggle("settings.syncDeleteFromXAfterSync", isOn: $settings.syncDeleteFromXAfterSync)

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
            } header: {
                Text("settings.sync")
            } footer: {
                Text("settings.sync.footer")
            }

            Section("settings.data") {
                LabeledContent("settings.localDatabase") {
                    Text("settings.localDatabaseValue")
                }
                Button("settings.clearCredentials", role: .destructive) {
                    try? KeychainStore.shared.clearAll()
                    refreshGrokState()
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            grokAPIKeyDraft = (try? KeychainStore.shared.load(.grokAPIKey)) ?? ""
            showAdvanced = settings.xClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            refreshGrokState()
        }
        .sheet(isPresented: $showEmbeddedLogin) {
            XWebLoginSheet { result in
                Task { await handleEmbeddedLogin(result) }
            }
        }
    }

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
                showAdvanced = true
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
            showAdvanced = true
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
