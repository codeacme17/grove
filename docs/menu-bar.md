# Menu-bar access

Grove displays its monochrome logo in the macOS menu bar while running. The
transparent template image lets macOS style the symbol for the menu bar's own
appearance, independently of Grove's Light or Dark preference.

## Actions

- **Open Grove** shows the existing main window, restores it if minimized, or
  opens it again after it was closed.
- **Add Project…** brings the main window forward and opens the existing native
  directory picker attached to that window. The File menu shortcut (⌘O) follows
  the same path. Adding is disabled while another picker is active or saved
  project storage is unavailable.
- The selected project's name is shown above **Refresh Worktrees**. Refresh uses
  the same asynchronous Git operation as the main window and is disabled during
  an active load. With no selected project, the menu shows that state instead.
- **Quit Grove** exits the application, including its menu-bar item.

Closing the main window keeps Grove running. This does not enable login launch
or continuous background scanning; the existing refresh behavior remains in
place. The Dock icon is retained. Use Quit Grove or ⌘Q to exit completely.

## Window coordination

The main scene has one stable identifier. A tiny AppKit view binds actions to its
actual window. If the scene has not created a window yet, a requested action waits
for that attachment event. There are no fixed-delay assumptions or window-title
searches. The pending action is consumed once before showing a folder picker.

## Verification

Check the template icon and menu actions with the window visible, minimized, and
closed. Confirm close does not terminate Grove, Open does not duplicate windows,
and Add opens a sheet on the reopened main window. Cancel the sheet, refresh a
selected project, and quit from the status menu. Check the shared File → Add
Project command after closing the window as well.
