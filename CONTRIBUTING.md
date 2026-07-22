# Contributing to EpycZones

Thank you for helping improve EpycZones. Changes should preserve its native,
local-first design and remain easy to inspect and package from a clean checkout.

## Development environment

- macOS 14 or later
- Xcode or Xcode Command Line Tools
- Swift 5.9 or later
- Accessibility permission for manual window-management testing

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

Repository-specific instructions for coding agents live in `AGENTS.md`.

## Validation

There is not yet an automated Swift test target. Before opening a pull request,
run the deterministic build and packaging checks relevant to the change:

```bash
make debug
make bundle
make dmg
```

For UI or window-management changes, also run `make run` and manually verify:

- Accessibility permission and first-launch behavior;
- global hotkeys and restore;
- Shift + Drag, cancellation, preview, and adjacent-zone spanning;
- edge and corner snap behavior;
- layout selection on affected displays and Spaces;
- app rules and workspace restore when relevant;
- Terminal, Xcode, Electron, or Chrome App Shim behavior when touched.

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
