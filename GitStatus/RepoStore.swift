import Foundation
import Observation
import AppKit

@Observable
final class RepoStore {
    var config: AppConfig {
        didSet { saveConfig() }
    }
    var statuses: [String: RepoStatus] = [:]

    var enabledRepos: [TrackedRepo] {
        config.trackedRepos.filter(\.enabled)
    }

    var worstState: RepoState {
        enabledRepos.compactMap { statuses[$0.path]?.state }.max() ?? .clean
    }

    var nonGreenCount: Int {
        enabledRepos.count { repo in
            guard let status = statuses[repo.path] else { return true }
            return status.state != .clean || status.error != nil
        }
    }

    var sortedRepos: [(TrackedRepo, RepoStatus)] {
        enabledRepos
            .map { repo in (repo, statuses[repo.path] ?? RepoStatus()) }
            .sorted { a, b in
                if (a.1.error != nil) != (b.1.error != nil) {
                    return a.1.error != nil
                }
                if a.1.state != b.1.state {
                    return a.1.state > b.1.state
                }
                return a.0.displayName.localizedCaseInsensitiveCompare(b.0.displayName) == .orderedAscending
            }
    }

    var groupedRepos: [(RepoState, [(TrackedRepo, RepoStatus)])] {
        let grouped = Dictionary(grouping: sortedRepos) { $0.1.state }
        return [RepoState.behind, .notPushed, .uncommitted, .clean].compactMap { state in
            guard let repos = grouped[state], !repos.isEmpty else { return nil }
            return (state, repos)
        }
    }

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GitStatus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.configURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = AppConfig()
        }
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    func addRepo(path: String) {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let repo = TrackedRepo(path: path, displayName: name, enabled: true)
        if !config.trackedRepos.contains(where: { $0.path == path }) {
            config.trackedRepos.append(repo)
        }
    }

    func removeRepo(path: String) {
        config.trackedRepos.removeAll { $0.path == path }
        statuses.removeValue(forKey: path)
    }

    func toggleRepo(path: String) {
        if let idx = config.trackedRepos.firstIndex(where: { $0.path == path }) {
            config.trackedRepos[idx].enabled.toggle()
        }
    }

    func openRepo(_ repo: TrackedRepo) {
        let url = URL(fileURLWithPath: repo.path)
        switch config.openWith {
        case .terminal:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Terminal", repo.path]
            try? proc.run()
        case .ghostty:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Ghostty", repo.path]
            try? proc.run()
        case .finder:
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
        case .custom(let appPath):
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}
