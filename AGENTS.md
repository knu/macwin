# Agent Notes

This repository builds `macwin`, a macOS command line tool for finding, OCRing, raising, and closing windows.

## Development

- Prefer `rg` and `fdfind` for code search.
- Use the existing SwiftPM and Makefile workflows.  `swift build` verifies the executable, and `make app` rebuilds `.build/MacWin.app`.
- Keep changes narrowly scoped to the behavior being fixed.  Avoid unrelated formatting churn.

## Testing and Verification

- When testing behavior that changes focus or window order, combine the action and its observation into one uninterrupted command sequence.  Ask for permission once for the whole sequence.  Do not run a focus-changing command, then ask for a second permission to inspect state, because switching back to the terminal can destroy the state being observed.
- Prefer running the built binary directly when testing:

  ```sh
  .build/MacWin.app/Contents/MacOS/macwin ...
  ```

- Avoid testing through `MacWin.app` launch or the `macwin-cli` wrapper unless that exact packaging path is under test.  Those paths rely on macOS Privacy & Security permissions for the app bundle.  If the permissions are missing, macOS may fail, prompt interactively, or change focus at the wrong time, making the test unreliable.
- For wrapper-specific tests, make sure the relevant Screen Recording and Accessibility permissions have already been granted before starting verification.
- GUI integration tests are opt-in.  Run them with `MACWIN_RUN_GUI_TESTS=1`; they should skip on GitHub Actions because hosted runners do not provide a reliable logged-in GUI session with TCC permissions.
- Test cleanup must not rely on AppleScript or other Apple Events that can hang on permission prompts.  Prefer `macwin`'s own window lookup and close paths, and put timeouts around any external helper process used by tests.
