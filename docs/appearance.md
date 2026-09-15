# Application appearance

Grove supports three application appearance preferences:

- **System** (default): follow the macOS appearance, including automatic changes.
- **Light**: use a light interface regardless of the system appearance.
- **Dark**: use a dark interface regardless of the system appearance.

Choose a preference from the **Appearance** toolbar button or **View → Appearance**.
Both controls show the same selection. The toolbar is available before a project
is added as well as while viewing worktrees.

The selection takes effect immediately and is saved in the app's UserDefaults
under `appearance`. It is restored when Grove is relaunched. The interface,
sidebar logo, empty-state logo, and running application icon follow the effective
appearance. Newly opened About panels and native folder pickers use the same
application appearance. Finder continues to show the default packaged icon.

System removes the application-specific override rather than copying the current
system color. This allows later system appearance changes to reach Grove. No
macOS-wide preference is changed. Git repositories and saved projects are unaffected.

## Verification

1. Switch Light → Dark from the toolbar and inspect the window and logo.
2. Confirm View → Appearance shows the same selection; switch back from that menu.
3. Open About Grove and the Add Project folder picker in the selected appearance.
4. Relaunch Grove with an explicit appearance selected and verify it is restored.
5. Choose System and verify the app clears its appearance override.
6. Verify application-icon updates still follow the effective color scheme.
