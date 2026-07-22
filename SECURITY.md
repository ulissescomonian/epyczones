# Security Policy

## Supported release

Security fixes are applied to the latest source on `main` and the current
GitHub Preview release. EpycZones 1.0 requires macOS 14 or later.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when
available. If that option is unavailable, contact the repository owner
privately instead of opening a public issue containing exploit details,
sensitive window titles, local paths, or other personal data.

Include the affected macOS version, EpycZones version, reproduction steps,
expected impact, and the smallest safe diagnostic sample. Do not include data
from unrelated applications or accounts.

## Preview trust model

The downloadable app uses a local code signature for bundle integrity. It is
not signed with Apple Developer ID, has no Apple Team ID, and is not notarized.
The DMG is also not signed or notarized. Gatekeeper can therefore require
Finder's **Open** flow or **System Settings → Privacy & Security → Open
Anyway**. Never disable Gatekeeper globally to install EpycZones.

Download the DMG and `.sha256` file from the same GitHub Release and verify:

```bash
shasum -a 256 -c EpycZones-1.0-arm64.dmg.sha256
```

## Permission and data scope

EpycZones needs macOS Accessibility permission because it inspects, moves, and
resizes windows from other apps. It is not sandboxed and uses Accessibility,
Core Graphics window information, global event monitoring, and Carbon hotkeys.
Space-aware layout selection also depends on private macOS APIs.

The application has no network client, cloud sync, account, analytics, or
telemetry. It persists settings locally in `UserDefaults` and JSON files under
`~/Library/Application Support/EpycZones/`. Some records contain application
bundle identifiers, display names, and window titles, which can reveal document
names or other sensitive context. Those files are not encrypted.

## Maintainer guidance

- Do not log window titles, secrets, or full user paths.
- Treat Accessibility and event-monitoring changes as security-sensitive.
- Validate all persisted data before using it to select applications or
  windows.
- Keep release packaging fail-closed for architecture, bundle identity,
  property list, signature, checksum, and absolute workspace path checks.
- Do not claim Developer ID signing or notarization unless Apple-issued
  credentials and notarization validation are actually in place.
