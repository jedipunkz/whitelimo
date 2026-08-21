#!/bin/sh
#
# Builds the app bundle and zips it for a release.
#
#     VERSION=v1.2.3 sh Scripts/package.sh
#
# ditto keeps the bundle's structure and its signature intact, which the zip
# command does not.
set -eu

APP_NAME=whitelimo
VERSION=${VERSION:-dev}
DIST=${DIST:-dist}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION="$VERSION" DIST="$DIST" sh Scripts/bundle.sh

ARCHIVE="$DIST/${APP_NAME}_${VERSION}_macos_universal.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ARCHIVE"

echo "Packaged $ARCHIVE"
