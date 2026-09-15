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

Git worktrees make it easy to work on several branches at once. Keeping track of them is harder: each task has its own folder, terminal, and local changes. As projects and parallel coding sessions add up, finding the right workspace becomes a task of its own.

Grove brings your projects and their worktrees into one native desktop app. See which branch lives where, inspect local changes, pull updates, and switch branches without losing your place. Keep projects in a sidebar or arrange them as tabs across the top—whichever fits the way you work.

**Less time finding your work. More time doing it.**

## Installation

Grove currently runs on **macOS 14 or later**. Install from source with a **Swift 6 toolchain** (Xcode or compatible Command Line Tools) and **Git**.

```sh
git clone https://github.com/codeacme17/grove.git
cd grove
make build-macos

mkdir -p "$HOME/Applications"
ditto apps/macos/dist/Grove.app "$HOME/Applications/Grove.app"
open "$HOME/Applications/Grove.app"
```

The app is installed in your user Applications folder. On first launch, choose **Add Project…** and select a Git repository or any of its worktrees. Grove discovers the rest automatically.

For development commands and build details, see the [macOS guide](apps/macos/README.md).

---

<p align="center">Licensed under the <a href="LICENSE">Apache License, Version 2.0</a>.</p>
