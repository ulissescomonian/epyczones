#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="EpycZones"
EXPECTED_ARCH="arm64"
EXPECTED_BUNDLE_IDENTIFIER="com.ulisses.epyczones"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"
DEFAULT_SIGNING_IDENTITY="EpycZones Dev"
EXPECTED_SIGNING_CERTIFICATE_SHA1="49625A7E53F7CAE22E7F9924B549DC28CC6D8700"
DEFAULT_APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"

fail() {
    print -u2 -- "package_app: $*"
    exit 1
}

for tool in swift ditto plutil codesign lipo strings security; do
    command -v "$tool" >/dev/null 2>&1 \
        || fail "required tool is unavailable: $tool"
done
[[ -x /usr/libexec/PlistBuddy ]] \
    || fail "required tool is unavailable: /usr/libexec/PlistBuddy"

INFO_PLIST_SOURCE="$ROOT_DIR/Resources/Info.plist"
ICON_SOURCE="$ROOT_DIR/.build/AppIcon.icns"
[[ -f "$INFO_PLIST_SOURCE" && ! -L "$INFO_PLIST_SOURCE" ]] \
    || fail "Info.plist is not a regular file: $INFO_PLIST_SOURCE"

APP_PATH="${APP_PATH:-$DEFAULT_APP_PATH}"
OVERWRITE="${OVERWRITE:-1}"
REQUIRE_STABLE_SIGNATURE="${REQUIRE_STABLE_SIGNATURE:-0}"
[[ "$OVERWRITE" == "0" || "$OVERWRITE" == "1" ]] \
    || fail "OVERWRITE must be 0 or 1"
[[ "$REQUIRE_STABLE_SIGNATURE" == "0" || "$REQUIRE_STABLE_SIGNATURE" == "1" ]] \
    || fail "REQUIRE_STABLE_SIGNATURE must be 0 or 1"

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$ROOT_DIR/$APP_PATH"
fi
[[ "${APP_PATH:t}" == "$APP_NAME.app" ]] \
    || fail "APP_PATH must end in $APP_NAME.app: $APP_PATH"

APP_PARENT="${APP_PATH:h}"
mkdir -p -- "$APP_PARENT"
[[ -d "$APP_PARENT" && ! -L "$APP_PARENT" ]] \
    || fail "application output parent is not a directory: $APP_PARENT"
APP_PARENT="$(cd "$APP_PARENT" && pwd -P)"
[[ "$APP_PARENT" != "/" ]] || fail "unsafe application output parent"
APP_PATH="$APP_PARENT/$APP_NAME.app"

plutil -lint "$INFO_PLIST_SOURCE" >/dev/null
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_SOURCE")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST_SOURCE")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST_SOURCE")"
PACKAGE_TYPE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO_PLIST_SOURCE")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST_SOURCE")"
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST_SOURCE")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST_SOURCE")"

[[ -n "$VERSION" && "$VERSION" != *[^A-Za-z0-9._-]* ]] \
    || fail "unsupported application version: $VERSION"
[[ -n "$BUILD" && "$BUILD" != *[^A-Za-z0-9._-]* ]] \
    || fail "unsupported application build: $BUILD"
[[ "$EXECUTABLE_NAME" == "$APP_NAME" ]] \
    || fail "expected executable $APP_NAME, found $EXECUTABLE_NAME"
[[ "$PACKAGE_TYPE" == "APPL" ]] \
    || fail "Info.plist does not describe an application bundle"
[[ "$BUNDLE_IDENTIFIER" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] \
    || fail "expected bundle identifier $EXPECTED_BUNDLE_IDENTIFIER, found $BUNDLE_IDENTIFIER"
[[ "$MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] \
    || fail "expected macOS minimum version $EXPECTED_MINIMUM_SYSTEM_VERSION, found $MINIMUM_SYSTEM_VERSION"
[[ "$ICON_FILE" == "AppIcon" || "$ICON_FILE" == "AppIcon.icns" ]] \
    || fail "expected CFBundleIconFile to reference AppIcon, found $ICON_FILE"

print -- "Building $APP_NAME $VERSION ($BUILD) for $EXPECTED_ARCH..."
swift build \
    --package-path "$ROOT_DIR" \
    -c release \
    --arch "$EXPECTED_ARCH"
"$ROOT_DIR/scripts/make_icon.sh" >/dev/null
[[ -f "$ICON_SOURCE" && ! -L "$ICON_SOURCE" ]] \
    || fail "application icon is not a regular file: $ICON_SOURCE"

BIN_DIR="$(swift build \
    --package-path "$ROOT_DIR" \
    -c release \
    --arch "$EXPECTED_ARCH" \
    --show-bin-path)"
EXECUTABLE_SOURCE="$BIN_DIR/$APP_NAME"
[[ -f "$EXECUTABLE_SOURCE" && -x "$EXECUTABLE_SOURCE" ]] \
    || fail "release executable not found: $EXECUTABLE_SOURCE"
[[ "$(lipo -archs "$EXECUTABLE_SOURCE")" == "$EXPECTED_ARCH" ]] \
    || fail "release executable is not exclusively $EXPECTED_ARCH"

# Compile-time paths can disclose a maintainer's machine in a public binary.
if LC_ALL=C strings "$EXECUTABLE_SOURCE" | grep -F "$ROOT_DIR" >/dev/null; then
    fail "absolute workspace path leaked into the release executable"
fi

if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    [[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] \
        || fail "refusing to replace non-directory application output: $APP_PATH"
    [[ "$OVERWRITE" == "1" ]] \
        || fail "application output already exists: $APP_PATH (set OVERWRITE=1 to replace it)"
fi

TEMP_DIR="$(mktemp -d "$APP_PARENT/.epyczones-app.XXXXXX")"
[[ -n "$TEMP_DIR" && -d "$TEMP_DIR" && "$TEMP_DIR" != "/" ]] \
    || fail "could not create a safe temporary directory"

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" && "$TEMP_DIR" != "/" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
on_interrupt() {
    cleanup
    trap - EXIT
    exit 130
}
on_terminate() {
    cleanup
    trap - EXIT
    exit 143
}
trap cleanup EXIT
trap on_interrupt INT
trap on_terminate TERM

TEMP_APP="$TEMP_DIR/$APP_NAME.app"
CONTENTS="$TEMP_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p -- "$MACOS" "$RESOURCES"

ditto --noqtn "$EXECUTABLE_SOURCE" "$MACOS/$APP_NAME"
chmod 0755 "$MACOS/$APP_NAME"
ditto --noqtn "$INFO_PLIST_SOURCE" "$CONTENTS/Info.plist"
ditto --noqtn "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Preserve a stable designated requirement so macOS TCC keeps Accessibility
# authorization across updates. Local contributor builds may fall back to
# ad-hoc; release packaging sets REQUIRE_STABLE_SIGNATURE=1 and fails closed.
REQUESTED_IDENTITY="${CODESIGN_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
REQUESTED_KEYCHAIN="${CODESIGN_KEYCHAIN:-}"
SIGNING_IDENTITY="-"
SIGNING_KEYCHAIN=""

identity_is_available() {
    local identity="$1"
    local keychain="${2:-}"
    if [[ -n "$keychain" ]]; then
        security find-identity -v -p codesigning "$keychain" 2>/dev/null \
            | grep -F -- "\"$identity\"" >/dev/null
    else
        security find-identity -v -p codesigning 2>/dev/null \
            | grep -F -- "\"$identity\"" >/dev/null
    fi
}

if [[ "$REQUESTED_IDENTITY" != "-" ]]; then
    if [[ -n "$REQUESTED_KEYCHAIN" && -f "$REQUESTED_KEYCHAIN" && ! -L "$REQUESTED_KEYCHAIN" ]]; then
        KEYCHAIN_PASSWORD="${CODESIGN_KEYCHAIN_PASSWORD:-}"
        security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$REQUESTED_KEYCHAIN" \
            >/dev/null 2>&1 || true
        if identity_is_available "$REQUESTED_IDENTITY" "$REQUESTED_KEYCHAIN"; then
            SIGNING_IDENTITY="$REQUESTED_IDENTITY"
            SIGNING_KEYCHAIN="$REQUESTED_KEYCHAIN"
        fi
    fi
    if [[ "$SIGNING_IDENTITY" == "-" ]] \
        && identity_is_available "$REQUESTED_IDENTITY"; then
        SIGNING_IDENTITY="$REQUESTED_IDENTITY"
    fi
fi

if [[ "$REQUIRE_STABLE_SIGNATURE" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
    fail "stable signing identity is required but unavailable: $DEFAULT_SIGNING_IDENTITY"
fi

typeset -a signing_args=(
    --force
    --options runtime
    --timestamp=none
    --sign "$SIGNING_IDENTITY"
)
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    signing_args+=(--keychain "$SIGNING_KEYCHAIN")
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -- "Signing ad-hoc (local build only; do not publish this artifact)."
else
    print -- "Signing with local identity: $SIGNING_IDENTITY"
fi
codesign "${signing_args[@]}" "$TEMP_APP"
codesign --verify --deep --strict "$TEMP_APP"

if [[ "$REQUIRE_STABLE_SIGNATURE" == "1" ]]; then
    DESIGNATED_REQUIREMENT="$(codesign -dr - "$TEMP_APP" 2>&1)"
    EXPECTED_CERTIFICATE_REQUIREMENT="certificate root = H\"${EXPECTED_SIGNING_CERTIFICATE_SHA1:l}\""
    [[ "$DESIGNATED_REQUIREMENT" == *"$EXPECTED_CERTIFICATE_REQUIREMENT"* ]] \
        || fail "release signature does not use the expected $DEFAULT_SIGNING_IDENTITY certificate"
fi

[[ "$(lipo -archs "$MACOS/$APP_NAME")" == "$EXPECTED_ARCH" ]] \
    || fail "packaged executable is not exclusively $EXPECTED_ARCH"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] \
    || fail "packaged bundle identifier changed unexpectedly"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] \
    || fail "packaged minimum system version changed unexpectedly"

if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    rm -rf -- "$APP_PATH"
fi
ditto --noqtn "$TEMP_APP" "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
print -- "$APP_PATH"
