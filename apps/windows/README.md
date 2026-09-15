# Grove for Windows

This directory is reserved for the native Windows application. No runnable Windows implementation is included yet, and its native framework has not been selected.

The Windows application will own its source, tests, dependencies, and build scripts here. Product behavior should follow the shared [MVP specification](../../docs/mvp.md), with platform-specific UI, filesystem access, and process integration.

The current Swift implementation remains in `apps/macos`. Choose any cross-platform code or fixture sharing when the Windows implementation establishes a concrete need.
