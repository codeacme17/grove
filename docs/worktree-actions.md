# Worktree actions

Each available, non-bare worktree card provides a Pull icon in its top-right corner. Click the branch name below the worktree title to switch branches. Click the path to copy it, or click the arrow button immediately beside it to reveal the worktree in Finder. The Finder button is disabled when the path is unavailable. Show Diff sits at the right of the path row. These extend the original read-only browser.

After a path is successfully copied, a “Path copied” toast appears at the bottom of the window for two seconds. Copying again restarts the timer. The toast does not block interaction or change the layout.

## Pull

- Pull uses the current branch's configured upstream with `git pull --ff-only --no-rebase --no-autostash --no-recurse-submodules`.
- A clean working tree is required, including staged, unstaged, and untracked files. Grove does not stash changes or force an update.
- Detached HEADs must switch to a local branch first. Missing upstreams, authentication failures, and divergent histories show Git's error.
- Existing Git authentication is used. Terminal prompts are disabled; authenticate outside Grove if necessary.
- The Pull command has a 120-second timeout. A failed or timed-out Pull can still have fetched remote references; Grove reloads the worktree list afterward.

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

`make test-macos` covers real local repositories and a local bare remote: fast-forward Pull into a linked worktree, divergent histories, dirty worktrees, occupied branches, missing upstreams, detached HEADs, missing paths, repository identity mismatches, staged/unstaged/untracked and binary diffs, unborn repositories, preview limits, and disabled external diff helpers.

The live-update integration test also saves files atomically, edits the same changed path twice, stages through a linked worktree's external index, renames, commits, creates and deletes untracked files, and verifies observation stops after cancellation.

For a UI check, use disposable repositories: expand change groups, select files (including renames and files with both staged and unstaged edits), select/copy patch text, switch a clean worktree to a free local branch, and Pull from a local test remote. Confirm loading and errors appear, unavailable actions are disabled, and the card refreshes after an operation. Do not use unrelated user repositories for write-operation tests.
