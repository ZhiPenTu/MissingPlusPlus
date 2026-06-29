#!/usr/bin/env bash
# Build a release .app and package it into a notarizable DMG.
#
# Two modes:
#   default (ad-hoc)        : local install only, no Developer ID needed.
#   DEVELOPER_ID=1           : real Developer ID signing + notarytool upload.
#
# For Developer ID mode you need:
#   * A Developer ID Application certificate in your keychain
#     (Xcode > Settings > Accounts > Manage Certificates).
#   * An app-specific password for your Apple ID
#     (https://appleid.apple.com > App-Specific Passwords).
#   * The credentials stored via:
#         xcrun notarytool store-credentials "missingpp-notary" \
#             --apple-id "<you@apple.com>" --team-id "<TEAMID>" --password "<app-pw>"
#   * Set NOTARY_PROFILE in the environment to the profile name (default: missingpp-notary).
#
# Re-runnable: cleans its own build/ and dist/ output.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/MissingPlusPlus.xcodeproj"
SCHEME="MissingPlusPlus"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
# VERSION 默认 1.0 (本地 build / dev 用)。release workflow 通过 env var 传入。
# 例子: VERSION=1.2.3 ./scripts/build-dmg.sh → MissingPlusPlus-1.2.3.dmg
VERSION="${VERSION:-1.0}"
DMG_NAME="MissingPlusPlus-${VERSION}.dmg"
VOL_NAME="Missing++"
STAGE_DIR="$BUILD_DIR/dmg-staging"
NOTARY_PROFILE="${NOTARY_PROFILE:-missingpp-notary}"

if [[ "${DEVELOPER_ID:-0}" == "1" ]]; then
    echo "==> mode: Developer ID signing + notarization"
    SIGN_IDENTITY="Developer ID Application"
    NEEDS_NOTARIZATION=1
else
    echo "==> mode: ad-hoc (local install only; no Developer ID needed)"
    SIGN_IDENTITY="-"  # ad-hoc
    NEEDS_NOTARIZATION=0
fi

echo "==> 1. Clean previous build/dist"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> 2. xcodebuild Release"
if [[ "$NEEDS_NOTARIZATION" == "1" ]]; then
    # Real signing — let Xcode pick the cert from the keychain.
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -derivedDataPath "$BUILD_DIR" \
      build \
      CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
      CODE_SIGN_STYLE=Manual \
      DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
else
    # Ad-hoc — match the project's automatic signing but force ad-hoc identity.
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -derivedDataPath "$BUILD_DIR" \
      build \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO
    # We disabled code signing in the xcodebuild call above so the binary
    # is unsigned; re-sign with ad-hoc so the DMG installs without errors.
    APP="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"
    codesign --force --deep --sign - "$APP" >/dev/null
fi

APP="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"
if [[ ! -d "$APP" ]]; then
    echo "ERROR: built .app not found at $APP" >&2
    exit 1
fi

if [[ "$NEEDS_NOTARIZATION" == "1" ]]; then
    echo "==> 3. Verify Developer ID signature"
    codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
    echo "    -> submitting to notarytool"
    # Staple later after we know the ticket is approved.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/MissingPlusPlus.zip"
    xcrun notarytool submit "$BUILD_DIR/MissingPlusPlus.zip" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "    -> notarization accepted, stapling ticket"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
else
    echo "==> 3. Re-sign with ad-hoc + verify"
    codesign --force --deep --sign - "$APP" >/dev/null
    codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
    spctl --assess --verbose=2 --type execute "$APP" 2>&1 | sed 's/^/    /' || true
fi

echo "==> 4. Stage DMG contents"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
ls -la "$STAGE_DIR"

echo "==> 5. Create DMG"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> 6. Verify DMG"
hdiutil verify "$DMG_PATH" && echo "    DMG verify OK"

echo "==> 7. Smoke-test: mount and inspect"
MOUNT_POINT=$(mktemp -d /tmp/mpp-mount.XXXXXX)
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -noverify -quiet
ls -la "$MOUNT_POINT"
hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT" 2>/dev/null || true

echo ""
echo "==> DONE"
echo "    DMG: $DMG_PATH"
ls -lh "$DMG_PATH"
