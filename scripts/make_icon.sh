#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_ICON="${SOURCE_ICON:-$ROOT_DIR/Resources/AppIcon.png}"
OUTPUT_ICON="${OUTPUT_ICON:-$ROOT_DIR/.build/AppIcon.icns}"

fail() {
    print -u2 -- "make_icon: $*"
    exit 1
}

for tool in sips iconutil; do
    command -v "$tool" >/dev/null 2>&1 \
        || fail "required tool is unavailable: $tool"
done

if [[ "$SOURCE_ICON" != /* ]]; then
    SOURCE_ICON="$ROOT_DIR/$SOURCE_ICON"
fi
if [[ "$OUTPUT_ICON" != /* ]]; then
    OUTPUT_ICON="$ROOT_DIR/$OUTPUT_ICON"
fi

[[ -f "$SOURCE_ICON" && ! -L "$SOURCE_ICON" ]] \
    || fail "source icon is not a regular file: $SOURCE_ICON"
[[ "${OUTPUT_ICON:t}" == "AppIcon.icns" ]] \
    || fail "OUTPUT_ICON must end in AppIcon.icns: $OUTPUT_ICON"

OUTPUT_PARENT="${OUTPUT_ICON:h}"
mkdir -p -- "$OUTPUT_PARENT"
[[ -d "$OUTPUT_PARENT" && ! -L "$OUTPUT_PARENT" ]] \
    || fail "icon output parent is not a directory: $OUTPUT_PARENT"
OUTPUT_PARENT="$(cd "$OUTPUT_PARENT" && pwd -P)"
[[ "$OUTPUT_PARENT" != "/" ]] || fail "unsafe icon output parent"
OUTPUT_ICON="$OUTPUT_PARENT/AppIcon.icns"

FORMAT="$(sips -g format "$SOURCE_ICON" | awk '/format:/ {print $2}')"
WIDTH="$(sips -g pixelWidth "$SOURCE_ICON" | awk '/pixelWidth:/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$SOURCE_ICON" | awk '/pixelHeight:/ {print $2}')"
HAS_ALPHA="$(sips -g hasAlpha "$SOURCE_ICON" | awk '/hasAlpha:/ {print $2}')"

[[ "$FORMAT" == "png" ]] || fail "source icon must be a PNG"
[[ "$WIDTH" == "1024" && "$HEIGHT" == "1024" ]] \
    || fail "source icon must be exactly 1024 x 1024 pixels"
[[ "$HAS_ALPHA" == "yes" ]] \
    || fail "source icon must contain an alpha channel"

TEMP_DIR="$(mktemp -d "$OUTPUT_PARENT/.epyczones-icon.XXXXXX")"
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

ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"
VERIFY_ICONSET_DIR="$TEMP_DIR/Verified.iconset"
TEMP_ICON="$TEMP_DIR/AppIcon.icns"
mkdir -p -- "$ICONSET_DIR"

typeset -a icon_specs=(
    "16 16 icon_16x16.png"
    "32 32 icon_16x16@2x.png"
    "32 32 icon_32x32.png"
    "64 64 icon_32x32@2x.png"
    "128 128 icon_128x128.png"
    "256 256 icon_128x128@2x.png"
    "256 256 icon_256x256.png"
    "512 512 icon_256x256@2x.png"
    "512 512 icon_512x512.png"
    "1024 1024 icon_512x512@2x.png"
)

local_spec=""
for local_spec in "${icon_specs[@]}"; do
    typeset -a fields=("${(z)local_spec}")
    sips -z "${fields[1]}" "${fields[2]}" "$SOURCE_ICON" \
        --out "$ICONSET_DIR/${fields[3]}" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$TEMP_ICON"
[[ -s "$TEMP_ICON" ]] || fail "iconutil produced an empty icon"

# A successful round trip rejects malformed ICNS output before publication.
iconutil -c iconset "$TEMP_ICON" -o "$VERIFY_ICONSET_DIR"
[[ -f "$VERIFY_ICONSET_DIR/icon_512x512@2x.png" ]] \
    || fail "generated ICNS failed validation"

mv -f -- "$TEMP_ICON" "$OUTPUT_ICON"
print -- "$OUTPUT_ICON"
