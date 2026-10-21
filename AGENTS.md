# Repository Guidelines

## Project Structure & Module Organization

EpycZones is a Swift 5.9 executable package targeting macOS 14. Application code lives in `Sources/EpycZones/`. Keep files grouped by responsibility: SwiftUI entry points and views (`EpycZonesApp.swift`, `SettingsView.swift`), layout and persistence models (`Layout.swift`, `LayoutStore.swift`), snapping logic (`WindowManager.swift`, `SnapHistory.swift`, `PostDragSnapCoordinator.swift`), Accessibility primitives and window lookup (`AXWindow.swift`, `WindowTargeting.swift`), and other macOS integrations (`DragDetector.swift`, `HotKeyManager.swift`). Convert between AppKit and Accessibility coordinates only through `ScreenCoordinates`, and write window frames only through `WindowManager.applyFrame`. `Resources/` contains the bundle plist and canonical 1024 px PNG app icon; `screenshots/` contains README assets; `scripts/` contains reproducible icon, app, and DMG packaging. Build products under `.build/` and `dist/` are ignored and must not be committed.

## Build, Test, and Development Commands

- `make debug` runs a fast development build with `swift build`.
- `make test` runs the unit tests with `swift test`.
- `make strict` builds with Swift 6 strict concurrency and fails on any warning. App types are `@MainActor`; system callbacks that already run on the main thread enter it with `MainActor.assumeIsolated`, and pure helpers stay `nonisolated` so tests can call them.
- `make screens` renders every window and pane to PNG in `.build/screens`, in light and dark mode and again in Brazilian Portuguese, from in-memory sample data. It never shows a window on screen, but the terminal needs the Screen Recording permission.
- `make strings` adds strings that are new in the code to `Resources/Localizable.xcstrings` and marks removed ones stale.
- `make build` creates the release executable.
- `make icon` regenerates and validates `.build/AppIcon.icns` from `Resources/AppIcon.png`.
- `make bundle` builds and assembles the local `.build/EpycZones.app`; it is a development artifact, not a distributable release.
- `make run` bundles and opens the app for manual testing.
- `make dmg` creates the versioned Apple Silicon DMG and SHA-256 sidecar in `dist/`.
- `make clean` removes SwiftPM and packaging artifacts.

## Packaging and Release Security

`scripts/` and `Resources/Info.plist` are functional-security hotspots, not cosmetic release metadata. Their changes can change the app identity seen by macOS TCC and silently revoke its ability to inspect and move other applications' windows.

- A release DMG must never contain an ad-hoc-signed app. Local `.build/EpycZones.app` bundles may be ad-hoc only for development and must not be published, copied to `/Applications` as a release candidate, or represented as a release artifact.
- The release signing identity is `EpycZones Dev` with certificate SHA-1 `49625A7E53F7CAE22E7F9924B549DC28CC6D8700`. The release bundle identifier must remain `com.ulisses.epyczones`.
- Release packaging must fail closed when that exact signing identity is unavailable; it must not fall back to another identity or ad-hoc signing. Packaging does not imply Apple Developer ID signing or notarization.
- Before publishing, compare the release candidate's designated requirement with the previous release. Any change to the signing requirement, certificate, bundle identifier, app path, or related `Info.plist` identity requires an explicit TCC migration plan, release notes that tell users to reauthorize Accessibility, and validation on an upgraded installed copy.
- Release validation includes `codesign --verify --deep --strict`, inspection of the signing identity and designated requirement, `make debug`, and manual Accessibility flows: Shift-drag zone snap, edge snap, and global hotkeys against another app.
- Only the designated release coordinator may modify release identity hotspots for a publication or publish a DMG/checksum. Other agents must provide a structured requested change to that coordinator.

## Coding Style & Naming Conventions

Use four-space indentation and opening braces on the declaration line. Name types and files in `UpperCamelCase` (`EdgeSnapResolver.swift`); use `lowerCamelCase` for functions, properties, and enum cases. Prefer narrow access control (`private`, `private(set)`), `// MARK: -` sections in larger files, and `///` comments for non-obvious APIs or coordinate-system decisions. No formatter or linter is configured, so match nearby code and keep diffs focused.

The interface is in English and Brazilian Portuguese. Write user-facing text as string literals in SwiftUI views or with `String(localized:)`, never assembled from pieces, and use `Text(verbatim:)` for data such as layout and display names. After adding or changing text, run `make strings` and translate the new entries in the catalog; `LocalizationTests` fails while any string lacks a translation or a translation changes its placeholders. Counts that need singular and plural forms get plural variations in the catalog. Packaging compiles the catalog into `en.lproj` and `pt-BR.lproj`.

## Testing Guidelines

Unit tests live in the `Tests/EpycZonesTests/` XCTest target, in files named `*Tests.swift`. They cover pure logic: snap geometry, zone hit-testing, edge resolution, and layout precedence. Keep new logic testable by separating it from `NSScreen`, Accessibility, and persisted state. There is no coverage requirement. Before every PR, run `make debug`, `make test` and `make strict`. For window-management or UI changes, also manually verify snapping, hotkeys, multi-monitor behavior where applicable, and Accessibility permission handling, with the bundle from `make bundle` launched by `open -n --env EPYCZONES_DATA_DIR=<copy>` against a copy of the data folder, never the user's own.

## Commit & Pull Request Guidelines

Follow the existing English, imperative commit style: `Add per-app rules...`, `Fix size cycle...`, or `Update README...`. Keep each commit scoped to one coherent change; use the body to explain behavior or architectural tradeoffs when needed. PRs should describe the user-visible effect, list validation performed, link related issues, and include screenshots for editor, settings, overlay, or menu-bar changes. Call out signing, Accessibility, or persistence implications explicitly.
