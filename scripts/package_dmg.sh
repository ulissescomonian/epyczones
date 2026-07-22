#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="EpycZones"
EXPECTED_ARCH="arm64"
EXPECTED_BUNDLE_IDENTIFIER="com.ulisses.epyczones"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"
EXPECTED_SIGNING_IDENTITY="EpycZones Dev"
EXPECTED_SIGNING_CERTIFICATE_SHA1="49625A7E53F7CAE22E7F9924B549DC28CC6D8700"
DEFAULT_APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
DEFAULT_OUTPUT_DIR="$ROOT_DIR/dist"

fail() {
    print -u2 -- "package_dmg: $*"
    exit 1
}

for tool in ditto hdiutil lipo shasum codesign strings plutil; do
    command -v "$tool" >/dev/null 2>&1 \
        || fail "required tool is unavailable: $tool"
done
[[ -x /usr/libexec/PlistBuddy ]] \
    || fail "required tool is unavailable: /usr/libexec/PlistBuddy"

APP_PATH="${APP_PATH:-$DEFAULT_APP_PATH}"
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
OVERWRITE="${OVERWRITE:-0}"
BUILD_APP="${BUILD_APP:-1}"
[[ "$OVERWRITE" == "0" || "$OVERWRITE" == "1" ]] \
    || fail "OVERWRITE must be 0 or 1"
[[ "$BUILD_APP" == "0" || "$BUILD_APP" == "1" ]] \
    || fail "BUILD_APP must be 0 or 1"

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$ROOT_DIR/$APP_PATH"
fi
if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

if [[ "$BUILD_APP" == "1" ]]; then
    APP_PATH="$APP_PATH" OVERWRITE=1 REQUIRE_STABLE_SIGNATURE=1 \
        "$ROOT_DIR/scripts/package_app.sh" >/dev/null
fi

[[ -d "$APP_PATH" && ! -L "$APP_PATH" ]] \
    || fail "application bundle is not a directory: $APP_PATH"
APP_PATH="$(cd "$APP_PATH" && pwd -P)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] \
    || fail "application Info.plist is not a regular file: $INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
PACKAGE_TYPE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$INFO_PLIST")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"

[[ -n "$VERSION" && "$VERSION" != *[^A-Za-z0-9._-]* ]] \
    || fail "unsupported application version: $VERSION"
[[ -n "$BUILD" && "$BUILD" != *[^A-Za-z0-9._-]* ]] \
    || fail "unsupported application build: $BUILD"
[[ "$PACKAGE_TYPE" == "APPL" ]] \
    || fail "input is not an application bundle: $APP_PATH"
[[ "$BUNDLE_IDENTIFIER" == "$EXPECTED_BUNDLE_IDENTIFIER" ]] \
    || fail "expected bundle identifier $EXPECTED_BUNDLE_IDENTIFIER, found $BUNDLE_IDENTIFIER"
[[ "$MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] \
    || fail "expected macOS minimum version $EXPECTED_MINIMUM_SYSTEM_VERSION, found $MINIMUM_SYSTEM_VERSION"
[[ -n "$EXECUTABLE_NAME" && "$EXECUTABLE_NAME" != */* ]] \
    || fail "invalid CFBundleExecutable value"

EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
[[ -f "$EXECUTABLE_PATH" && -x "$EXECUTABLE_PATH" ]] \
    || fail "application executable not found or not executable: $EXECUTABLE_PATH"
[[ "$(lipo -archs "$EXECUTABLE_PATH")" == "$EXPECTED_ARCH" ]] \
    || fail "application executable is not exclusively $EXPECTED_ARCH"
codesign --verify --deep --strict "$APP_PATH" \
    || fail "application signature verification failed"
DESIGNATED_REQUIREMENT="$(codesign -dr - "$APP_PATH" 2>&1)"
EXPECTED_CERTIFICATE_REQUIREMENT="certificate root = H\"${EXPECTED_SIGNING_CERTIFICATE_SHA1:l}\""
[[ "$DESIGNATED_REQUIREMENT" == *"$EXPECTED_CERTIFICATE_REQUIREMENT"* ]] \
    || fail "release app must use $EXPECTED_SIGNING_IDENTITY ($EXPECTED_SIGNING_CERTIFICATE_SHA1); ad-hoc or changed identities cannot preserve Accessibility authorization"
if LC_ALL=C strings "$EXECUTABLE_PATH" | grep -F "$ROOT_DIR" >/dev/null; then
    fail "absolute workspace path leaked into the packaged executable"
fi

[[ -n "$OUTPUT_DIR" && "$OUTPUT_DIR" != "/" ]] \
    || fail "unsafe output directory"
mkdir -p -- "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] \
    || fail "output path is not a directory: $OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
[[ "$OUTPUT_DIR" != "/" ]] || fail "unsafe output directory"

DMG_NAME="$APP_NAME-$VERSION-$EXPECTED_ARCH.dmg"
CHECKSUM_NAME="$DMG_NAME.sha256"
TARGET_DMG="$OUTPUT_DIR/$DMG_NAME"
TARGET_CHECKSUM="$OUTPUT_DIR/$CHECKSUM_NAME"

validate_output_targets() {
    local target
    for target in "$TARGET_DMG" "$TARGET_CHECKSUM"; do
        [[ "${target:h}" == "$OUTPUT_DIR" ]] \
            || fail "refusing unsafe output target: $target"
        if [[ -e "$target" || -L "$target" ]]; then
            [[ -f "$target" && ! -L "$target" ]] \
                || fail "refusing to overwrite non-regular output target: $target"
            [[ "$OVERWRITE" == "1" ]] \
                || fail "output already exists: $target (set OVERWRITE=1 to replace verified regular files)"
        fi
    done
}

validate_output_targets

TEMP_DIR="$(mktemp -d "$OUTPUT_DIR/.epyczones-dmg.XXXXXX")"
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

STAGING_DIR="$TEMP_DIR/staging"
TEMP_DMG="$TEMP_DIR/$DMG_NAME"
TEMP_CHECKSUM="$TEMP_DIR/$CHECKSUM_NAME"
mkdir -p -- "$STAGING_DIR"

ditto --noqtn "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
[[ "$(readlink "$STAGING_DIR/Applications")" == "/Applications" ]] \
    || fail "could not create the Applications shortcut"

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$TEMP_DMG" >/dev/null
hdiutil verify "$TEMP_DMG" >/dev/null

DIGEST="$(shasum -a 256 "$TEMP_DMG" | awk '{print $1}')"
[[ "$DIGEST" != *[^0-9a-f]* && ${#DIGEST} == 64 ]] \
    || fail "could not calculate a valid SHA-256 checksum"
printf '%s  %s\n' "$DIGEST" "$DMG_NAME" > "$TEMP_CHECKSUM"

validate_output_targets
mv -f -- "$TEMP_DMG" "$TARGET_DMG"
mv -f -- "$TEMP_CHECKSUM" "$TARGET_CHECKSUM"

hdiutil verify "$TARGET_DMG" >/dev/null
(
    cd "$OUTPUT_DIR"
    shasum -a 256 -c "$CHECKSUM_NAME" >/dev/null
)

print -- "$TARGET_DMG"
print -- "$TARGET_CHECKSUM"
