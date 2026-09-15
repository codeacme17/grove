# Grove MVP

Grove is a native macOS app for seeing every registered Git worktree in a project.

## Requirements

- Build a SwiftUI desktop app, with AppKit integration where needed, for macOS 14 or later.
- Add a local Git project using a native folder picker. Accept the main worktree, a linked worktree, or a subdirectory.
- Identify projects by the canonical common Git directory, not their display name or branch. Adding another worktree of the same repository selects the existing project.
- Persist added projects across launches. Removing a project only removes its saved entry.
- List all worktrees registered by Git, including those outside the project folder, the main worktree, detached HEADs, locked worktrees, and stale registrations.
- Show each worktree's folder name, full path, branch or short commit, and relevant Git flags. A registered worktree is not evidence of a running agent.
- Refresh on request and when the app becomes active. Show loading, empty, and actionable error states without presenting old data as current.
- Keep Git work off the main thread. Bound command duration and support cancellation.
- Use the installed Git CLI. Do not mutate repositories or scan arbitrary folders for repositories.
- Provide a repeatable local build that produces a launchable macOS app bundle.

## Verification

Use temporary real repositories to verify linked worktree discovery, deduplication, detached HEADs, paths with whitespace, locked and deleted worktrees, and non-repository errors. Test persistence and malformed saved data. Build the SwiftUI executable and app bundle; visually inspect the app if UI access is available.

## Out of scope

Worktree creation/deletion, commits, diffs, agent activity detection, remote hosting integration, Windows implementation, App Store distribution, signing and notarization for distribution.
