import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    var store: RepoStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScanDirectoriesTab(store: store)
                .tabItem { Label("Scan", systemImage: "folder.badge.questionmark") }
            ReposTab(store: store)
                .tabItem { Label("Repos", systemImage: "list.bullet") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

// MARK: - Scan Directories Tab

struct ScanDirectoriesTab: View {
    var store: RepoStore
    @State private var discoveredRepos: [String] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isScanning = false
    @State private var selectedDir: String?

    var body: some View {
        VStack(spacing: 0) {
            // Directory list with toolbar-style buttons
            GroupBox {
                VStack(spacing: 0) {
                    List(store.config.scanDirectories, id: \.self, selection: $selectedDir) { dir in
                        Label(dir, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            addScanDirectory()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            if let sel = selectedDir {
                                store.config.scanDirectories.removeAll { $0 == sel }
                                selectedDir = nil
                            }
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedDir == nil)

                        Spacer()

                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Scan for Repos") {
                            scan()
                        }
                        .disabled(store.config.scanDirectories.isEmpty || isScanning)
                    }
                    .padding(8)
                }
            } label: {
                Text("Scan Directories")
            }
            .padding()

            // Discovered repos
            if !discoveredRepos.isEmpty {
                GroupBox {
                    VStack(spacing: 0) {
                        List {
                            ForEach(discoveredRepos, id: \.self) { path in
                                let alreadyTracked = store.config.trackedRepos.contains { $0.path == path }
                                Toggle(isOn: Binding(
                                    get: { selectedPaths.contains(path) },
                                    set: { sel in
                                        if sel { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
                                    }
                                )) {
                                    HStack {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                        if alreadyTracked {
                                            Text("already tracked")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                }
                                .disabled(alreadyTracked)
                            }
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))

                        Divider()

                        HStack {
                            Text("\(discoveredRepos.count) repos found")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Add Selected (\(selectedPaths.count))") {
                                for path in selectedPaths {
                                    store.addRepo(path: path)
                                }
                                discoveredRepos.removeAll { selectedPaths.contains($0) }
                                selectedPaths.removeAll()
                            }
                            .disabled(selectedPaths.isEmpty)
                        }
                        .padding(8)
                    }
                } label: {
                    Text("Discovered Repos")
                }
                .padding([.horizontal, .bottom])
            }

            Spacer(minLength: 0)
        }
    }

    private func addScanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to scan for git repos"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !store.config.scanDirectories.contains(path) {
                store.config.scanDirectories.append(path)
            }
        }
    }

    private func scan() {
        isScanning = true
        discoveredRepos = []
        selectedPaths = []
        let dirs = store.config.scanDirectories
        Task.detached {
            var all: [String] = []
            for dir in dirs {
                all.append(contentsOf: RepoScanner.scanDirectory(dir))
            }
            let unique = Array(Set(all)).sorted()
            await MainActor.run {
                discoveredRepos = unique
                selectedPaths = Set(unique.filter { path in
                    !store.config.trackedRepos.contains { $0.path == path }
                })
                isScanning = false
            }
        }
    }
}

// MARK: - Repos Tab

struct ReposTab: View {
    var store: RepoStore

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.config.trackedRepos) { repo in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { repo.enabled },
                            set: { _ in store.toggleRepo(path: repo.path) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(repo.displayName)
                                .font(.body)
                            Text(repo.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            store.removeRepo(path: repo.path)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Text("\(store.config.trackedRepos.count) repos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Repo...") {
                    addIndividualRepo()
                }
            }
            .padding(12)
        }
        .padding()
    }

    private func addIndividualRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a git repository folder"
        if panel.runModal() == .OK, let url = panel.url {
            let gitDir = url.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue {
                store.addRepo(path: url.path)
            }
        }
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    var store: RepoStore
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Polling") {
                Picker("Check every", selection: Binding(
                    get: { store.config.pollIntervalMinutes },
                    set: { store.config.pollIntervalMinutes = $0 }
                )) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }

                Picker("Fetch from remote", selection: Binding(
                    get: { store.config.fetchEveryNthCycle },
                    set: { store.config.fetchEveryNthCycle = $0 }
                )) {
                    Text("Every cycle").tag(1)
                    Text("Every 2nd cycle").tag(2)
                    Text("Every 3rd cycle").tag(3)
                    Text("Every 5th cycle").tag(5)
                }
            }

            Section("Display") {
                Toggle("Warn when working on main or master", isOn: Binding(
                    get: { store.config.showDefaultBranchWarning },
                    set: { store.config.showDefaultBranchWarning = $0 }
                ))
            }

            Section("Open repos with") {
                Picker("Application", selection: Binding(
                    get: {
                        switch store.config.openWith {
                        case .terminal: return 0
                        case .ghostty: return 1
                        case .finder: return 2
                        case .custom: return 3
                        }
                    },
                    set: { val in
                        switch val {
                        case 0: store.config.openWith = .terminal
                        case 1: store.config.openWith = .ghostty
                        case 2: store.config.openWith = .finder
                        default: store.config.openWith = .custom(path: "")
                        }
                    }
                )) {
                    Text("Terminal").tag(0)
                    Text("Ghostty").tag(1)
                    Text("Finder").tag(2)
                    Text("Custom app...").tag(3)
                }
                .pickerStyle(.radioGroup)

                if case .custom(let path) = store.config.openWith {
                    HStack {
                        TextField("App path", text: Binding(
                            get: { path },
                            set: { store.config.openWith = .custom(path: $0) }
                        ))
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowedContentTypes = [.application]
                            if panel.runModal() == .OK, let url = panel.url {
                                store.config.openWith = .custom(path: url.path)
                            }
                        }
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: { setLaunchAtLogin($0) }
                ))

                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Disabled in System Settings. Allow GitStatus under Login Items.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                } else if loginStatus == .notFound {
                    Text("macOS cannot find the app. Move GitStatus to /Applications and try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        .formStyle(.grouped)
    }

    private func refreshLoginStatus() {
        loginStatus = LoginItem.status
        store.config.launchAtLogin = LoginItem.isRegistered
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            loginError = "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        refreshLoginStatus()
        if enabled, loginStatus == .requiresApproval {
            LoginItem.openSystemSettings()
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("GitStatus")
                .font(.title)
                .fontWeight(.semibold)

            Text("v1.1")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 4) {
                Text("Created by")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Titans of Industry", destination: URL(string: "https://titansofindustry.be")!)
                    .font(.caption)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
