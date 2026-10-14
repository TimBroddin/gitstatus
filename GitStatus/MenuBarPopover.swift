import SwiftUI

enum RepoFilter: CaseIterable {
    case all, behind, notPushed, uncommitted, clean

    var label: String {
        switch self {
        case .all: "All"
        case .behind: "Behind"
        case .notPushed: "Unpushed"
        case .uncommitted: "Dirty"
        case .clean: "Clean"
        }
    }

    var state: RepoState? {
        switch self {
        case .all: nil
        case .behind: .behind
        case .notPushed: .notPushed
        case .uncommitted: .uncommitted
        case .clean: .clean
        }
    }

    var color: Color {
        switch self {
        case .all: .primary
        case .behind: .red
        case .notPushed: .orange
        case .uncommitted: .yellow
        case .clean: .green
        }
    }
}

struct MenuBarPopover: View {
    var store: RepoStore
    var monitor: GitMonitor?
    @Environment(\.openWindow) private var openWindow
    @State private var filter: RepoFilter = .all

    private var filteredRepos: [(TrackedRepo, RepoStatus)] {
        guard let state = filter.state else { return store.sortedRepos }
        return store.sortedRepos.filter { $0.1.state == state }
    }

    private func count(for filter: RepoFilter) -> Int {
        guard let state = filter.state else { return store.enabledRepos.count }
        return store.sortedRepos.count { $0.1.state == state }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Git Status")
                    .font(.headline)
                Spacer()
                if monitor?.isRefreshing == true {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                Button {
                    monitor?.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Status bar
            if !store.enabledRepos.isEmpty {
                StatusBar(store: store, filter: $filter)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()

            if store.enabledRepos.isEmpty {
                Spacer()
                Text("No repos tracked yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text("Open Settings to add repositories.")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.top, 2)
                Spacer()
            } else if filteredRepos.isEmpty {
                Spacer()
                Text("No repos in this category.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRepos, id: \.0.id) { repo, status in
                            Button {
                                store.openRepo(repo)
                            } label: {
                                RepoRow(repo: repo, status: status, showDot: filter == .all, showDefaultBranchWarning: store.config.showDefaultBranchWarning)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Push") {
                                    GitActions.push(path: repo.path) {
                                        monitor?.refresh()
                                    }
                                }
                                Button("Pull") {
                                    GitActions.pull(path: repo.path) {
                                        monitor?.refresh()
                                    }
                                }
                                Divider()
                                Button("Open") {
                                    store.openRepo(repo)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer
            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct StatusBar: View {
    var store: RepoStore
    @Binding var filter: RepoFilter

    private var segments: [(RepoFilter, Int)] {
        [RepoFilter.behind, .notPushed, .uncommitted, .clean].map { f in
            let c = store.sortedRepos.count { $0.1.state == f.state }
            return (f, c)
        }
    }

    private var total: Int {
        store.enabledRepos.count
    }

    var body: some View {
        VStack(spacing: 4) {
            // The bar
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(segments, id: \.0) { seg, count in
                        if count > 0 {
                            let fraction = CGFloat(count) / CGFloat(max(total, 1))
                            let isSelected = filter == seg
                            let isAll = filter == .all

                            seg.color
                                .opacity(isSelected || isAll ? 1 : 0.3)
                                .overlay {
                                    if fraction * geo.size.width > 24 {
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .frame(width: max(fraction * geo.size.width - 1.5, 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    filter = filter == seg ? .all : seg
                                }
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend below when filtered
            if filter != .all, let state = filter.state {
                HStack(spacing: 4) {
                    Circle()
                        .fill(filter.color)
                        .frame(width: 6, height: 6)
                    Text(state.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

struct RepoRow: View {
    let repo: TrackedRepo
    let status: RepoStatus
    var showDot: Bool = true
    var showDefaultBranchWarning: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if showDot {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(repo.displayName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)
                    if showDefaultBranchWarning, status.onDefaultBranch {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("On default branch")
                    }
                    if let warning = status.fetchWarning {
                        Image(systemName: "icloud.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(warning)
                    }
                }
                HStack(spacing: 4) {
                    Text(status.currentBranch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let error = status.error {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .help(error)
                    } else if showDot, status.state != .clean {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(status.state.label)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        if status.error != nil { return .gray }
        switch status.state {
        case .clean: return .green
        case .uncommitted: return .yellow
        case .notPushed: return .orange
        case .behind: return .red
        }
    }
}

// MARK: - Git Actions

enum GitActions {
    static func push(path: String, completion: @escaping () -> Void) {
        Task.detached {
            _ = GitChecker.runGit(in: path, args: ["push"])
            await MainActor.run { completion() }
        }
    }

    static func pull(path: String, completion: @escaping () -> Void) {
        Task.detached {
            _ = GitChecker.runGit(in: path, args: ["pull"])
            await MainActor.run { completion() }
        }
    }

}
