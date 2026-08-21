#!/bin/sh
#
# Builds whitelimo and assembles whitelimo.app.
#
#     VERSION=v1.2.3 sh Scripts/bundle.sh
#
# The binary is universal (arm64 + x86_64) unless UNIVERSAL=0 is set, which is
# useful while developing because a single-architecture build is much quicker.
# The bundle is signed ad hoc: whitelimo has no paid Developer ID, and macOS
# needs some signature to keep the app's identity stable across launches.
set -eu

APP_NAME=whitelimo
VERSION=${VERSION:-dev}
DIST=${DIST:-dist}
UNIVERSAL=${UNIVERSAL:-1}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ "$UNIVERSAL" = "1" ]; then
	ARCHES="--arch arm64 --arch x86_64"
else
	ARCHES=""
fi

# CFBundleShortVersionString is what the menu shows, so it keeps whatever was
# asked for minus the leading "v". CFBundleVersion has to be a dotted number, so
# anything that is not one (a branch build, say) becomes 0.0.0.
SHORT_VERSION=$(printf '%s' "${VERSION#v}" | tr -c 'A-Za-z0-9._+-' '-')
case "$SHORT_VERSION" in
[0-9]*.[0-9]*.[0-9]*) BUILD_VERSION=$(printf '%s' "$SHORT_VERSION" | sed 's/[-+].*$//') ;;
*) BUILD_VERSION=0.0.0 ;;
esac

echo "Building $APP_NAME $SHORT_VERSION"
# shellcheck disable=SC2086
swift build -c release $ARCHES
# shellcheck disable=SC2086
BIN_DIR=$(swift build -c release $ARCHES --show-bin-path)

APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

sed -e "s|@SHORT_VERSION@|$SHORT_VERSION|" -e "s|@BUILD_VERSION@|$BUILD_VERSION|" \
	Resources/Info.plist >"$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"

ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
swift Scripts/make-icon.swift "$ICONSET"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$ICONSET"

# --force replaces the signature swift build may already have applied.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
