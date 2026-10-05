# Worktree actions

Each available, non-bare worktree card provides a Pull icon in its top-right corner. Click the branch name below the worktree title to switch branches. Click the path to copy it, or click the arrow button immediately beside it to reveal the worktree in Finder. The Finder button is disabled when the path is unavailable. Show Diff sits at the right of the path row. These extend the original read-only browser.

After a path is successfully copied, a “Path copied” toast appears at the bottom of the window for two seconds. Copying again restarts the timer. The toast does not block interaction or change the layout.

## Create Worktree

The project toolbar's **Create Worktree** button opens a sheet with New Branch (default) and Existing Branch modes. New Branch accepts a new name and a local base branch, defaulting to the main worktree's branch when available. If the main worktree is detached or bare, explicitly choose a local base. Repositories without any committed local branch cannot create a worktree yet. Existing Branch lists local branches and disables those already checked out elsewhere.

Grove suggests `<repository-parent>/grove-worktrees/<branch-directory>`. Branch names containing slashes get a safe single-directory suggestion, such as `feature/new-task` → `feature-new-task`. Edit the full absolute path or use **Choose Parent Folder**. Existing files, directories (including empty ones), and symlinks are rejected; nothing is overwritten. Invalid or conflicting names, missing bases, and occupied branches are checked again on submission. Grove does not fetch, guess remote branches, or accept tags/arbitrary commits as bases.

After creation, Grove refreshes the project and scrolls to the new worktree when that project remains selected. It does not launch an editor or terminal.

## Delete Worktree

Each card's actions menu includes **Delete Worktree…**. This removes the directory and its Git worktree registration, including worktrees created outside Grove. It preserves the local branch and commits. **Remove from Grove** remains a separate project action that only removes the saved entry.

The confirmation sheet names the worktree and full directory path, describes the disk effects, and checks deletion eligibility. Deletion rechecks repository identity, the registered root, and eligibility before using non-forced `git worktree remove`.

- Main worktrees, bare entries, locked worktrees, detached HEADs, and missing/stale paths cannot be deleted.
- Staged, unstaged, untracked, and ignored content block deletion. Grove also checks for gitlinks/submodules and nested `.git` repositories, including repositories embedded in otherwise tracked directories.
- The sheet or menu explains why an operation is unavailable. Preserve content or resolve the condition outside Grove, then check again.
- There is no force, stash, unlock, branch deletion, pruning, or recursive filesystem-deletion fallback.

After removal, Grove refreshes the project and clears details and cached changes for removed worktrees.

## Operation coordination

Creation, deletion, Pull, and branch switching share a single write-operation guard, including project-scoped creation before a target exists. Switching projects does not redirect an operation. Grove refreshes the affected project's snapshot after success, failure, or cancellation; another selected project keeps its own results.

Create/delete Git writes have a 120-second timeout. Their sheets show progress and provide **Stop** while an operation is running. Stopping or failing does not imply rollback: a failed checkout hook, for example, may leave a new branch, directory, and registration. Grove reports the observed remaining state when a Git write fails and does not destructively clean it up. External Git processes do not share Grove's operation guard; final Git errors are surfaced if state changes during an action.

## Pull

- Pull uses the current branch's configured upstream with `git pull --ff-only --no-rebase --no-autostash --no-recurse-submodules`.
- A clean working tree is required, including staged, unstaged, and untracked files. Grove does not stash changes or force an update.
- Detached HEADs must switch to a local branch first. Missing upstreams, authentication failures, and divergent histories show Git's error.
- Existing Git authentication is used. Terminal prompts are disabled; authenticate outside Grove if necessary.
- The Pull command has a 120-second timeout. A failed or timed-out Pull can still have fetched remote references; Grove reloads the worktree list afterward.
- Pull results appear as a toast at the bottom of the window instead of a message inside the worktree card or a modal alert. Success toasts name the worktree and disappear after three seconds; failures include the error and remain for six seconds. Toasts can be dismissed, and a new notification replaces the previous one and restarts its timer.

## Switch Branch

- The picker lists existing local branches. Remote-only branches must be created locally using Git first.
- Branches checked out in another worktree are marked as in use and disabled. Git rechecks occupancy when switching.
- Switching requires a clean working tree. Grove does not force checkout, reset branches, or create branches implicitly.
- The repository identity and worktree root are verified before each action. Missing paths and bare repositories are not actionable.
- Grove serializes its Pull and switch operations, then refreshes the selected project's worktree metadata. Switching projects does not redirect an operation to a different worktree.

## Local Diff

- Show Diff appears only when local changes are available and includes the changed-file count, such as `Show Diff (3)`. Paths are counted once even when they appear in both staged and unstaged sections. A clean worktree has no Diff button; if an expanded worktree becomes clean after refreshing, its list collapses. Status is read when the card appears and after project refreshes or worktree operations, including while the list is collapsed. A failed read shows an error and a retry action rather than treating the worktree as clean.
- Show Diff expands a panel inside the card, with a compact file list grouped into Changes, Staged Changes, Untracked, and Merge Changes (when present). It compares local changes, not the branch against main.
- Each collapsible group shows its file count. Rows show a file icon, filename, muted directory, and Git status letter. Clicking a file selects it and opens its patch in a full-height panel on the right of the window. Selecting another file updates that panel. The panel has a close button, independent scrolling, and a draggable divider to adjust its width. On narrow windows the project sidebar temporarily hides while the panel is open, then returns when the panel closes. Renames include the original path in the tooltip and preview header.
- File lists, counts, and the selected patch update automatically when files or Git metadata change; neither Diff view has a manual refresh button. Every mounted card watches its worktree and the common Git directory, including linked worktree indexes. Native filesystem events are coalesced over 300 ms, with at most one pending status reload while a read is running. If the event service cannot start, a two-second polling fallback preserves automatic updates. Project changes, view removal, and Git operations cancel observation; returning to the card or finishing an operation starts a fresh read and watcher.
- Closing the detail panel cancels its unfinished read and clips its width to zero while retaining its document view. Reopening restores the previous content and scroll position before refreshing. Collapsing Show Diff hides the file list while keeping the selected file open and updating on the right. Switching projects closes the detail panel. A selected change that disappears from Git status closes the detail panel.
- Text additions, deletions, and hunk headers are colored. Binary changes display Git's binary-file summary. Untracked directories are listed without recursively diffing embedded repositories.
- All changed files are listed; patches are loaded on selection and limited to 200 KB per file, with a visible truncation notice. The native text view supports selection and scrolling without creating a SwiftUI row for every line.
- Preview commands disable external diff helpers and text conversion and do not stage or modify files.

## Loading behavior

- Refreshing the same project keeps the last successful worktree list and expanded change lists visible. Duplicate in-flight worktree refresh requests are coalesced; visited projects keep per-project snapshots and restore immediately on return. For a first visit, the previous project stays visible with actions disabled until the new project is ready; the title and worktrees switch together.
- Diff refreshes retain the existing native text view, scroll position, and text selection (clamped if the content shrinks). When switching files, the previous document stays visible until the new file's title and patch can be replaced together. Failed reads report an error with a Retry action while keeping the last successful content.
- Change lists cache up to 16 worktrees, including group expansion state; mounted cards retain their own list state. Hiding a list keeps its view mounted, and the card continues to refresh its status and file count. Its first expansion uses the already loaded file list, revealing the complete section with a height transition. Hidden lists and panels are excluded from interaction and accessibility. The collapse animation wraps the whole card, including its background and border, so the visible content and card bounds shrink together. Transitions respect Reduce Motion.
- Loading indicators appear after 250 ms and, once visible, remain for at least 300 ms. Results are applied as soon as they arrive; only the indicator's visibility is delayed. Buttons keep stable labels and dimensions.

## Verification

`make test-macos` also covers creation with new/existing branches, destination/name conflicts, branch occupancy changes, branch/commit preservation, unsafe deletion cases (including ignored files and nested repositories), partial creation failures, cancellation, and project switching.

Existing tests cover real local repositories and a local bare remote: fast-forward Pull into a linked worktree, divergent histories, dirty worktrees, occupied branches, missing upstreams, detached HEADs, missing paths, repository identity mismatches, staged/unstaged/untracked and binary diffs, unborn repositories, preview limits, and disabled external diff helpers.

The live-update integration test also saves files atomically, edits the same changed path twice, stages through a linked worktree's external index, renames, commits, creates and deletes untracked files, and verifies observation stops after cancellation.

For a UI check, use disposable repositories: expand change groups, select files (including renames and files with both staged and unstaged edits), select/copy patch text, switch a clean worktree to a free local branch, and Pull from a local test remote. Confirm loading and errors appear, unavailable actions are disabled, and the card refreshes after an operation. Do not use unrelated user repositories for write-operation tests.

For lifecycle UI verification, use disposable repositories: create with each mode, edit the suggested destination, confirm occupied branches are unavailable, inspect deletion blockers and the confirmation path, remove a clean linked worktree, and verify its branch still exists.
