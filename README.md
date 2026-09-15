<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="apps/macos/Sources/Grove/Resources/AppIconDark.png">
    <img src="apps/macos/Sources/Grove/Resources/AppIcon.png" alt="Grove logo" width="112" height="112">
  </picture>
</p>

<h1 align="center">Grove</h1>

<p align="center">A home for your Git worktrees.</p>

<br>

## Why Grove

Vibe coding makes it easy to hand several tasks to AI coding agents at once. As agents work in parallel, they create Git worktrees to keep their changes isolated. Those worktrees quickly multiply across projects and folders, making it hard to see what exists, which branch each worktree uses, and what has changed—all at a glance.

Grove gives you a visual home for those worktrees. It brings your projects, branches, paths, and local changes together in one native desktop app, so you can navigate and manage the workspaces your agents create. Inspect diffs, pull updates, and switch branches without hunting through folders and terminals. Keep projects in a sidebar or arrange them as tabs across the top—whichever fits the way you work.

**Less time finding your work. More time doing it.**

## Installation

Grove runs on **macOS 14 or later**, on **Apple Silicon and Intel** Macs. Git must be installed and available on your Mac.

1. Download [Grove for macOS](https://github.com/codeacme17/grove/releases/latest).
2. Unzip the download and move **Grove.app** to your Applications folder.
3. Open Grove, choose **Add Project…**, and select a Git repository or any of its worktrees. Grove discovers the rest automatically.

The initial release is ad-hoc signed and has not been notarized by Apple. macOS may block the downloaded app; see the release notes for details. You can also build it locally:

<details>
<summary>Build and install from source</summary>

Requires a **Swift 6 toolchain** (Xcode or compatible Command Line Tools) and **Git**.

```sh
git clone https://github.com/codeacme17/grove.git
cd grove
make build-macos

mkdir -p "$HOME/Applications"
ditto apps/macos/dist/Grove.app "$HOME/Applications/Grove.app"
open "$HOME/Applications/Grove.app"
```

The app is installed in your user Applications folder.

</details>

For development commands and build details, see the [macOS guide](apps/macos/README.md).

---

<p align="center">Licensed under the <a href="LICENSE">Apache License, Version 2.0</a>.</p>
