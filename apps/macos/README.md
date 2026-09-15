<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Sources/Grove/Resources/AppIconDark.png">
    <img src="Sources/Grove/Resources/AppIcon.png" alt="Grove logo" width="144" height="144">
  </picture>
</p>

# Grove for macOS

A native macOS home for your Git worktrees. Built with SwiftUI and Swift.

## MVP

- Add a repository, any linked worktree, or a folder inside one.
- Discover every registered worktree, even outside the project directory.
- See branch names, detached commits, locks, stale registrations, and full paths.
- Refresh with **⌘R** or when returning to the app.
- Save projects between launches. **Remove from Grove** only removes a saved entry.
- Right-click the project navigation and choose **Switch to Top** for horizontal project tabs, or **Switch to Sidebar** to return. The layout persists between launches; tabs scroll horizontally when needed.
- Drag sidebar projects or top tabs to reorder them. Right-click a project to rename or remove it; names and order persist between launches. Renaming changes its display name in Grove, not its folder or Git identity.
- Copy worktree paths or reveal them in Finder.

Worktree cards also support **Pull**, **Switch Branch…**, and **Show Diff**. Pull and branch switching require a clean working tree; diffs are read-only. See [worktree actions](../../docs/worktree-actions.md). A worktree's presence does not indicate that an agent is running.

## Build and run

Run the following commands from `apps/macos`. From the repository root, use `make test-macos`, `make build-macos`, or `make run-macos`.

Requires macOS 14+, Swift 6 toolchain (Xcode or compatible Command Line Tools), and Git. The MVP has no third-party dependencies.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Grove.app
```

For a faster development build, use `bash scripts/build-app.sh debug`. Open `Package.swift` in Xcode to inspect or develop the package. The script creates the app bundle; no generated Xcode project is required.

The test script also supports Command Line Tools installations that bundle Swift Testing but do not automatically add its framework and macro search paths. With full Xcode selected, it delegates directly to `swift test`.

The bundle targets the machine's architecture and is ad-hoc signed for local use. A public release needs Developer ID signing and notarization. This initial build is not an App Sandbox or Mac App Store build; Git needs access to worktrees outside the selected folder.

Menu-bar access: [open, add, refresh, and quit](../../docs/menu-bar.md).

Appearance controls: [System, Light, and Dark](../../docs/appearance.md).

## Design

- `Sources/Grove`: SwiftUI interface and observable workspace state.
- `Sources/GroveCore`: Git process execution, repository identity, worktree parsing, and persistence.
- `Tests/GroveCoreTests`: real temporary Git repositories, parser, persistence, timeout, and cancellation tests.
- `Tests/GroveTests`: project ordering, renaming, removal, and persistence failure tests for workspace state.

Project identity is the canonical common Git directory. Worktree data comes from `git worktree list --porcelain -z`; paths are passed as process arguments, never interpolated into shell commands. Git operations run off the UI thread, with a 15-second command timeout (120 seconds for Pull). Superseded reads are cancelled; user-requested writes run to completion or timeout. Temporary output files avoid pipe-buffer deadlocks.

Projects are stored in `~/Library/Application Support/Grove/projects.json`. A damaged file is preserved and reported instead of silently overwritten. Restore valid JSON and use **Retry** if this occurs.

Grove looks for Git at `/opt/homebrew/bin/git`, `/usr/local/bin/git`, then `/usr/bin/git`. On macOS, the last path may require installing Command Line Tools with `xcode-select --install`.

Scope and acceptance criteria: [MVP specification](../../docs/mvp.md). Future Windows work will use a native UI and share product rules and test scenarios.
