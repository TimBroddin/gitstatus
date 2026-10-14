# GitStatus

A macOS menubar app that monitors the git status of your local repositories at a glance.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange)

## Features

- **Menubar icon** with colored badge showing how many repos need attention
- **Stacked status bar** — proportional colored bar showing the distribution of repo states
- **Click to filter** by status category
- **Scan directories** to auto-discover git repos with checkbox selection
- **Configurable polling** interval (1–30 minutes) with periodic remote fetch
- **Click a repo** to open it in Terminal, Finder, or a custom app
- **Launch at login** support

## Status States

| Color | State | Meaning |
|-------|-------|---------|
| Red | Behind | Remote has commits you haven't pulled |
| Orange | Not pushed | Local commits ahead of remote |
| Yellow | Uncommitted | Modified or untracked files |
| Green | Clean | Everything in sync |

An additional warning badge appears when you're working directly on `main` or `master` (can be turned off in Settings).

## Install

```bash
brew tap TimBroddin/tap
brew install --cask gitstatus
```

Or download the latest release from the [Releases page](https://github.com/TimBroddin/gitstatus/releases).

## Getting Started

1. Click the branch icon in your menubar
2. Open Settings and add a scan directory (e.g. `~/Projects`)
3. Scan for repos and select which ones to track

## Building from Source

1. Open the project in Xcode
2. Build and run (macOS 14.0+)

### Requirements

- macOS 14.0+
- Xcode 15+
- Git (via `/usr/bin/git`)

## Architecture

- **GitStatusApp** — `MenuBarExtra` entry point, renders menubar icon with status badge
- **MenuBarPopover** — Popover with status bar, filtered repo list, refresh button
- **RepoStore** — `@Observable` data store with JSON persistence in Application Support
- **GitMonitor** — Background polling service running git commands via `Process`
- **RepoScanner** — Recursive `.git` directory discovery
- **SettingsView** — Tabbed settings: General, Scan, Repos, About

## License

Copyright 2026 [Titans of Industry](https://titansofindustry.be)
