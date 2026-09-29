#!/usr/bin/env bash
# Builds build/TouchTabs.app (universal, ad-hoc signed) with the browser
# extension bundled inside. Set ARCH=native for a faster single-arch build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/TouchTabs.app"

cd "$ROOT/app"
if [[ "${ARCH:-universal}" == "universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=()
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/TouchTabs"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchTabs"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"

ICONS="$(mktemp -d)"
trap 'rm -rf "$ICONS"' EXIT
"$BIN" --render-icons "$ICONS"
iconutil -c icns "$ICONS/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp -R "$ROOT/extension" "$APP/Contents/Resources/Extension"

codesign --force --sign - "$APP"
echo "Built $APP"
