#!/bin/bash
# Builds a distributable Petal.dmg and puts it on the website.
#
#   tools/release.sh                      build + sign with whatever identity is available, make the DMG
#   PETAL_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/release.sh
#   PETAL_NOTARY_PROFILE=petal-notary tools/release.sh     also notarize and staple (see below)
#
# Notarization needs a paid Apple Developer account and a "Developer ID Application" certificate. Without them the
# DMG still works, but macOS asks people to confirm the first launch (Control-click → Open).
# One-time setup for notarization:
#   xcrun notarytool store-credentials petal-notary --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD_DIR="$ROOT/build-release"
APP="$BUILD_DIR/Build/Products/Release/Petal.app"
DMG="$BUILD_DIR/Petal-$VERSION.dmg"

# Which identity signs the app?
IDENTITY=${PETAL_SIGN_IDENTITY:-}
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)".*/\1/' || true)
fi
if [ -z "$IDENTITY" ] && [ -f Config/Local.xcconfig ]; then
  IDENTITY=$(grep -m1 '^CODE_SIGN_IDENTITY' Config/Local.xcconfig | sed -E 's/^CODE_SIGN_IDENTITY *= *//')
  [ -n "$IDENTITY" ] && echo "No Developer ID certificate found: signing with \"$IDENTITY\" from Config/Local.xcconfig. The DMG will run, but is not notarizable."
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "No signing identity found: signing ad hoc. The DMG will run on this Mac, but is not notarizable."
fi
echo "Signing identity: $IDENTITY"
case "$IDENTITY" in "Developer ID Application"*) TIMESTAMP="--timestamp" ;; *) TIMESTAMP="--timestamp=none" ;; esac

echo "== Building Petal $VERSION (Release, arm64)"
xcodegen generate >/dev/null
xcodebuild -project Petal.xcodeproj -scheme Petal -configuration Release -derivedDataPath "$BUILD_DIR" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="$IDENTITY" build 2>&1 | grep -E "error:|warning: .*(sign|entitle)|BUILD (SUCCEEDED|FAILED)" || true
[ -d "$APP" ] || { echo "Build failed"; exit 1; }

echo "== Signing with the hardened runtime (engines first, then the app)"
for tool in ffmpeg cwebp; do
  codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP/Contents/Resources/Engines/$tool"
done
codesign --force --options runtime $TIMESTAMP --entitlements "$ROOT/tools/Petal.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "== Making the disk image"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Petal.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Petal" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force $TIMESTAMP --sign "$IDENTITY" "$DMG" 2>/dev/null || true

NOTARIZED=""
if [ -n "${PETAL_NOTARY_PROFILE:-}" ]; then
  echo "== Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PETAL_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  NOTARIZED="--notarized"
fi

echo "== Updating the website"
python3 "$ROOT/tools/stamp-site.py" "$DMG" "$VERSION" $NOTARIZED
echo "Done: $DMG"
