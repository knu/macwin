# macwin

A macOS command line tool for finding, OCRing, and raising windows.

`macwin` enumerates application windows, filters them by title or predicate, optionally runs OCR on window-local rectangles, and can raise or close matching windows.  It is packaged as `MacWin.app` so macOS privacy permissions are granted to the app bundle rather than to every caller application.

## Installation

Build and install the app bundle:

```console
% make install-app
```

This installs `MacWin.app` to `~/Applications`.  Use the wrapper script to launch the app-backed CLI:

```console
% bin/macwin-cli --help
```

## Usage

```console
% macwin find (--app NAME | --bundle-id ID | --window-id ID) [OPTIONS]
% macwin raise --window-id ID
% macwin close --window-id ID
```

Find Edge windows:

```console
% bin/macwin-cli find --bundle-id com.microsoft.Edge --pretty
```

Filter by title and stop after the first match:

```console
% bin/macwin-cli find --app "Microsoft Edge" --title-regex Dashboard --limit 1 --pretty
```

Raise a specific window:

```console
% bin/macwin-cli raise --window-id 12345
```

Close a specific window:

```console
% bin/macwin-cli close --window-id 12345
```

Find and raise matching windows:

```console
% bin/macwin-cli find --bundle-id com.microsoft.Edge --title-regex Dashboard --raise --exit-status
```

## OCR

Use `--ocr` to recognize text from one or more window-local rectangles:

```console
% bin/macwin-cli find --bundle-id com.microsoft.Edge \
  --ocr '0,0,400,120;name=header' \
  --where 'ANY ocr.text MATCHES ".*Dashboard.*"' \
  --pretty
```

OCR rectangles use logical coordinates with the origin at the window's top-left corner.

- Negative `X` and `Y` are relative to the right and bottom edge.
- `W` or `H` of `0` means the remaining width or height.
- Negative `W` or `H` means the remaining width or height minus that many points.
- `;name=NAME` tags OCR tokens from that rectangle.
- `;save_image=PATH` writes the cropped image for inspection.

## Options

- `--app NAME` — Match application name.
- `--bundle-id ID` — Match bundle identifier.
- `--window-id ID` — Match a specific CG window ID.
- `--title-regex REGEX` — Match the window title.
- `--ocr X,Y,W,H[;name=NAME][;save_image=PATH]` — OCR a window-local rectangle.  Repeatable.
- `--where NSPREDICATE` — Filter with an `NSPredicate`.  Repeatable; predicates are ANDed.
- `--lang ja,en` — OCR recognition languages.
- `--min-confidence VALUE` — Discard OCR tokens below the confidence value.
- `--limit COUNT` — Stop after finding this many windows.
- `--exit-status` — Exit with status 1 if no windows matched.
- `--raise` — Raise matched windows.
- `--include-offscreen` — Include offscreen windows.
- `--ax` — Include `ax_title` in JSON output.
- `--pretty` — Pretty-print JSON.

The `title` field prefers `CGWindowName` and falls back to `SCWindow.title` when needed.

## Output

`find` writes JSON to stdout:

```json
{
  "windows": [
    {
      "window_id": 12345,
      "pid": 678,
      "app_name": "Microsoft Edge",
      "bundle_id": "com.microsoft.Edge",
      "title": "Home - Microsoft Edge",
      "bounds": { "x": 0, "y": 25, "w": 1440, "h": 900 }
    }
  ]
}
```

With OCR:

```json
{
  "windows": [
    {
      "window_id": 12345,
      "ocr": [
        {
          "name": "header",
          "text": "Home Dashboard",
          "confidence": 0.98,
          "bbox": { "x": 40, "y": 8, "w": 160, "h": 20 }
        }
      ]
    }
  ]
}
```

## Permissions

- Screen Recording — Required for OCR and `SCWindow.title` fallback.
- Accessibility — Required for `raise`, `close`, and `--ax`.

## Author

Copyright (c) 2026 Akinori Musha.

Licensed under the MIT license.  See `LICENSE` for details.

Visit the [GitHub Repository](https://github.com/knu/macwin) for the latest information.
