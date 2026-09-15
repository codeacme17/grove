# Grove

A native macOS home for your Git worktrees. Built with SwiftUI and Swift.

## MVP

- Add a repository, any linked worktree, or a folder inside one.
- Discover every registered worktree, even outside the project directory.
- See branch names, detached commits, locks, stale registrations, and full paths.
- Refresh with **⌘R** or when returning to the app.
- Save projects between launches. **Remove from Grove** only removes a saved entry.
- Copy worktree paths or reveal them in Finder.

Grove does not modify repositories. A worktree's presence does not indicate that an agent is running.

## Build and run

Requires macOS 14+, Swift 6 toolchain (Xcode or compatible Command Line Tools), and Git. The MVP has no third-party dependencies.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open dist/Grove.app
```

For a faster development build, use `bash scripts/build-app.sh debug`. Open `Package.swift` in Xcode to inspect or develop the package. The script creates the app bundle; no generated Xcode project is required.

The test script also supports Command Line Tools installations that bundle Swift Testing but do not automatically add its framework and macro search paths. With full Xcode selected, it delegates directly to `swift test`.

The bundle targets the machine's architecture and is ad-hoc signed for local use. A public release needs Developer ID signing and notarization. This initial build is not an App Sandbox or Mac App Store build; Git needs access to worktrees outside the selected folder.

## Design

- `Sources/Grove`: SwiftUI interface and observable workspace state.
- `Sources/GroveCore`: Git process execution, repository identity, worktree parsing, and persistence.
- `Tests/GroveCoreTests`: real temporary Git repositories, parser, persistence, timeout, and cancellation tests.

Project identity is the canonical common Git directory. Worktree data comes from `git worktree list --porcelain -z`; paths are passed as process arguments, never interpolated into shell commands. Git operations run off the UI thread, have a 15-second timeout, and are cancelled when superseded. Temporary output files avoid pipe-buffer deadlocks.

Projects are stored in `~/Library/Application Support/Grove/projects.json`. A damaged file is preserved and reported instead of silently overwritten. Restore valid JSON and use **Retry** if this occurs.

Grove looks for Git at `/opt/homebrew/bin/git`, `/usr/local/bin/git`, then `/usr/bin/git`. On macOS, the last path may require installing Command Line Tools with `xcode-select --install`.

Scope and acceptance criteria: [MVP specification](docs/mvp.md). Future Windows work will use a native UI and share product rules and test scenarios.
