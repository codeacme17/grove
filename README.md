# Grove

A home for your Git worktrees, with native desktop apps for each operating system.

## Platforms

| Platform | Status | Implementation |
| --- | --- | --- |
| [macOS](apps/macos/README.md) | Working MVP | SwiftUI, AppKit, Swift 6; macOS 14+ |
| [Windows](apps/windows/README.md) | Planned | Native Windows framework to be selected |

## Repository layout

```text
apps/
  macos/
    Package.swift
    Sources/
      Grove/          # macOS interface and workspace state
      GroveCore/      # Swift Git integration and persistence
    Tests/
    scripts/          # macOS build, test, and diagnostic tools
  windows/            # Future native Windows application
docs/                # Product requirements and project documentation
Makefile              # Root shortcuts for platform commands
```

Each application owns its source, tests, dependencies, build scripts, and generated artifacts. Product requirements and documentation live in `docs/`. GroveCore currently belongs to the macOS application; Windows will have its own native implementation. Add shared code or fixtures only when both applications actually consume them.

## macOS quick start

Requires macOS 14+, a Swift 6 toolchain (Xcode or compatible Command Line Tools), and Git. From the repository root:

```sh
make test-macos
make build-macos
make run-macos
```

The app is built at `apps/macos/dist/Grove.app`. For a debug build, use `make build-macos CONFIGURATION=debug`. Open `apps/macos/Package.swift` in Xcode for development. See the [macOS guide](apps/macos/README.md) for platform details.

## MVP

Add a local Git project and browse all its registered worktrees, including linked worktrees outside the project folder, detached HEADs, and stale registrations. Projects persist between launches. Repository operations are read-only.

See the [MVP specification](docs/mvp.md) for acceptance criteria. Windows implementation is planned and is not part of this MVP.
