# Contributing to EpycZones

Thank you for helping improve EpycZones. Changes should preserve its native,
local-first design and remain easy to inspect and package from a clean checkout.

## Development environment

- macOS 14 or later
- Xcode or Xcode Command Line Tools
- Swift 5.9 or later
- Accessibility permission for manual window-management testing
- Screen Recording permission for your terminal, only to render screens with
  `make screens`

Clone the repository and run a development build:

```bash
git clone https://github.com/ulissescomonian/EpycZones.git
cd EpycZones
make debug
```

## Project conventions

- Keep Swift source under `Sources/EpycZones/` and match the surrounding
  four-space style.
- Use `UpperCamelCase` for types and files and `lowerCamelCase` for functions,
  properties, and enum cases.
- Prefer narrow access control and focused changes.
- Explain coordinate-system conversions, Accessibility behavior, and private
  API assumptions when they are not obvious.
- Do not add telemetry, network access, or persistence of additional window
  metadata without documenting the privacy impact.
- Keep generated app bundles, DMGs, checksums, and `.build/` products out of
  Git.

## Translations

The interface is in English and Brazilian Portuguese and follows the language
of macOS. Write user-facing text as string literals in SwiftUI views or with
`String(localized:)`, never assembled from pieces, and use `Text(verbatim:)`
for data such as layout and display names.

After adding or changing text, run `make strings`. It adds new strings to
`Resources/Localizable.xcstrings` and marks removed ones stale; then translate
the new entries. `LocalizationTests` fails while a string lacks a Portuguese
translation or a translation changes its placeholders. Counts that need
singular and plural forms get plural variations in the catalog.

Repository-specific instructions for coding agents live in `AGENTS.md`.

## Validation

Unit tests in `Tests/EpycZonesTests/` cover snap geometry, zone hit-testing,
edge resolution, layout precedence, the editor's geometry and editing session,
persistence, and translations. They run with a private temporary data folder
and never read or change your own layouts. Before opening a pull request, run
the tests and the deterministic build and packaging checks relevant to the
change:

```bash
make debug
make test
make strict
make bundle
make dmg
```

`make strict` builds with Swift 6 strict concurrency and fails on any warning.

For changes to a window or pane, run `make screens`. It renders every window
and pane to PNG in `.build/screens`, in light and dark mode and again in
Brazilian Portuguese, from sample data and without showing anything on screen.
Attach the relevant renders to the pull request.

For UI or window-management changes, also verify by hand:

- Accessibility permission and first-launch behavior;
- global hotkeys and restore;
- Shift + Drag, cancellation, preview, and adjacent-zone spanning;
- edge and corner snap behavior;
- layout selection on affected displays and Desktops (Spaces);
- app rules and workspace restore when relevant;
- Terminal, Xcode, Electron, or Chrome App Shim behavior when touched.

Test the development bundle from `make bundle` against a copy of your data
folder, so a mistake never touches your own layouts. Quit any other running
copy of EpycZones first, since two copies would both respond to drags and
shortcuts, and launch it with `open` so macOS attributes the Accessibility
permission to the app rather than to the terminal:

```bash
cp -R ~/Library/Application\ Support/EpycZones /tmp/epyczones-data
open -n --env EPYCZONES_DATA_DIR=/tmp/epyczones-data .build/EpycZones.app
```

The distributed build is `arm64`. `make bundle` validates the bundle property
list, architecture, icon, path hygiene, and code signature. `make dmg` adds the
Applications shortcut, verifies the image, and writes a SHA-256 sidecar.

## Pull requests

Use a concise English imperative title and describe:

- the user-visible behavior;
- the implementation or architectural tradeoff;
- validation performed;
- Accessibility, persistence, signing, or private-API implications;
- screenshots for changes to the editor, overlays, Settings, or menu bar.

Keep each pull request focused. Link related issues and call out any behavior
that could differ across macOS versions, window toolkits, displays, or Spaces.

## Release packaging

The public Preview is locally signed and is not notarized. Maintainers can
select a local identity with `CODESIGN_IDENTITY` and `CODESIGN_KEYCHAIN`; other
contributors receive an ad-hoc signature automatically. Never describe either
one as an Apple-trusted Developer ID signature.

Release assets belong on the GitHub Release, not in the repository:

```text
dist/EpycZones-<version>-arm64.dmg
dist/EpycZones-<version>-arm64.dmg.sha256
```

Verify the mounted image and checksum before publishing both files together.
Before publishing, also compare the designated requirement of the new app with
the previous release (`codesign -d -r- EpycZones.app`). A different signing
identity or bundle identifier makes macOS revoke the Accessibility permission
on update.
