# Worktree list layout freeze

## Symptom and evidence

After adding a repository with ten worktrees, Grove stopped responding. Two live process samples showed the main thread continuously executing SwiftUI view-graph transactions, including `LazyLayoutViewCache.updateItemPhases` and `AppKitPopUpAdaptor.PlatformView.updateNSView`.

- First capture: 99% CPU, 22.2 GB physical footprint, 1,487 / 1,489 main-thread samples in layout transactions.
- Second capture after restarting and re-adding the project: 99% CPU, 7.4 GB physical footprint, 1,514 / 1,517 samples in layout transactions.
- The underlying Git command returned ten worktrees in 16 ms.

## Fix shape

Replace the worktree `LazyVStack` with `VStack`. This removes lazy row-phase transitions from the feedback loop while preserving row contents, menus, repository identity, and refresh behavior. The MVP now constructs all worktree rows eagerly.

This is a narrow mitigation of the observed rendering loop, not a claim to have identified a specific defect inside SwiftUI. Isolated row and full-app layout probes did not deterministically recreate the freeze; the actual app did recur during interactive testing. Git and persistence unit tests alone cannot catch this failure.

## Regression check

1. Build the app with `make build-macos`.
2. Open it and add a repository with multiple worktrees, including long branch names and detached or stale entries.
3. Scroll through the list, open and dismiss row menus, change window width, and switch away and back.
4. Leave the application idle, then run `python3 apps/macos/scripts/check-ui-idle.py --pid <pid>`.
5. Repeat after several minutes to check for delayed runaway behavior.

The checker samples the main thread and fails if at least 80% of samples are inside SwiftUI layout transactions. Both captured freezes fail this check. A successful check is an observation of that interval, not proof that every possible future interaction is safe.

The first fixed-build check reported 0 / 2,625 samples in layout transactions, 0% CPU, and approximately 124 MB resident memory after re-adding the same project. The six existing core tests also passed.

Captured user repository paths and full process samples remain local diagnostic artifacts and are not committed.
