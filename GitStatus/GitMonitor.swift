import Foundation

@Observable
final class GitMonitor {
    private var timer: Timer?
    private var cycleCount = 0
    private let store: RepoStore
    var isRefreshing = false

    init(store: RepoStore) {
        self.store = store
    }

    func start() {
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(store.config.pollIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        cycleCount += 1
        let shouldFetch = (cycleCount % store.config.fetchEveryNthCycle) == 0
        let repos = store.enabledRepos

        Task.detached {
            var results: [String: RepoStatus] = [:]
            for repo in repos {
                let status = GitChecker.checkRepo(path: repo.path, fetch: shouldFetch)
                results[repo.path] = status
            }
            await MainActor.run { [results] in
                for (path, status) in results {
                    self.store.statuses[path] = status
                }
                self.isRefreshing = false
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

// Fully nonisolated so git Process calls never touch the main actor
nonisolated enum GitChecker {
    struct GitResult {
        var output: String
        var errorOutput: String
        var exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    /// Candidate git binaries. /usr/bin/git is only a shim that forwards to the Command Line Tools
    /// or Xcode, and it stops working when those are missing or stale (typically after a macOS upgrade).
    private static let gitCandidates = [
        "/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ]

    /// First git binary that actually runs, cached after the first successful lookup.
    private static let gitPathLock = NSLock()
    nonisolated(unsafe) private static var cachedGitPath: String?

    private static func resolveGitPath() -> (path: String?, failure: String?) {
        gitPathLock.lock()
        defer { gitPathLock.unlock() }
        if let cachedGitPath { return (cachedGitPath, nil) }

        var firstFailure: String?
        for candidate in gitCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            let result = run(executable: candidate, arguments: ["--version"])
            if let result, result.succeeded {
                cachedGitPath = candidate
                return (candidate, nil)
            }
            if firstFailure == nil {
                let detail = result?.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                firstFailure = detail.isEmpty ? "\(candidate) failed to run" : detail
            }
        }
        return (nil, firstFailure ?? "git not found. Install the Command Line Tools with: xcode-select --install")
    }

    static func checkRepo(path: String, fetch: Bool) -> RepoStatus {
        var fetchWarning: String?
        if fetch {
            let result = runGitResult(in: path, args: ["fetch", "--quiet"])
            if !result.succeeded {
                fetchWarning = "Fetch failed: " + firstLine(of: result.errorOutput)
            }
        }

        let porcelain = runGitResult(in: path, args: ["status", "--porcelain"])
        guard porcelain.succeeded else {
            // Never report "clean" when git did not actually answer.
            return RepoStatus(
                lastChecked: Date(),
                error: "git failed: " + firstLine(of: porcelain.errorOutput),
                fetchWarning: fetchWarning
            )
        }
        let hasUncommitted = !porcelain.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Fails when the branch has no upstream, which is a legitimate "nothing to compare" case
        // now that we know git itself works.
        let revList = runGitResult(in: path, args: ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        var ahead = 0
        var behind = 0
        if revList.succeeded {
            let parts = revList.output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                ahead = Int(parts[0]) ?? 0
                behind = Int(parts[1]) ?? 0
            }
        }

        let branchResult = runGitResult(in: path, args: ["symbolic-ref", "--short", "HEAD"])
        let branch = branchResult.succeeded
            ? branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            : "unknown"
        let onDefault = (branch == "main" || branch == "master")

        let state: RepoState
        if behind > 0 {
            state = .behind
        } else if ahead > 0 {
            state = .notPushed
        } else if hasUncommitted {
            state = .uncommitted
        } else {
            state = .clean
        }

        return RepoStatus(
            state: state,
            onDefaultBranch: onDefault,
            currentBranch: branch,
            lastChecked: Date(),
            fetchWarning: fetchWarning
        )
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? "unknown error" : line
    }

    /// Runs git and returns its output, or nil if it failed (non-zero exit or could not be launched).
    static func runGit(in directory: String, args: [String]) -> String? {
        let result = runGitResult(in: directory, args: args)
        return result.succeeded ? result.output : nil
    }

    static func runGitResult(in directory: String, args: [String]) -> GitResult {
        let resolved = resolveGitPath()
        guard let gitPath = resolved.path else {
            return GitResult(output: "", errorOutput: resolved.failure ?? "git not found", exitCode: -1)
        }
        return run(executable: gitPath, arguments: ["-C", directory] + args)
            ?? GitResult(output: "", errorOutput: "could not launch \(gitPath)", exitCode: -1)
    }

    private static func run(executable: String, arguments: [String]) -> GitResult? {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Never block on a credential or SSH prompt: fail instead of hanging the poll loop.
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stderr concurrently so a chatty git cannot fill the pipe and deadlock.
        let errBox = DataBox()
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()
        return GitResult(
            output: String(data: outData, encoding: .utf8) ?? "",
            errorOutput: String(data: errBox.data, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
