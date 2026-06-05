#!/bin/bash
# build_app.sh — Build ZeroG as a macOS .app bundle
#
# Usage:
#   ./build_app.sh                 Unsigned local build (for development)
#   ZEROG_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build_app.sh
#                                  Signed build (hardened runtime + entitlements)
#   ZEROG_SIGN_IDENTITY=... ZEROG_NOTARY_PROFILE="zerog-notary" ./build_app.sh
#                                  Signed + notarized + stapled (release build)
#
# The signing/notarization steps are skipped automatically when the matching
# environment variable is unset, so this script works for both local dev and
# release without edits. See docs/distribution-signing.md for one-time setup.
#
# Output: ./build/ZeroG.app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ZeroG"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$SCRIPT_DIR/ZeroG/Resources/ZeroG.entitlements"

# Signing / notarization config — supplied via environment, never hardcoded.
SIGN_IDENTITY="${ZEROG_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${ZEROG_NOTARY_PROFILE:-}"

echo "🚀 Building ZeroG..."

# 1. Build release binary with Swift Package Manager
cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY_PATH="$SCRIPT_DIR/.build/release/$APP_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Build failed: binary not found at $BINARY_PATH"
    exit 1
fi

echo "✅ Binary built successfully"

# 2. Create .app bundle structure
echo "📦 Packaging into $APP_NAME.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 5. Copy resources (gemini prompt, assets)
if [ -d "$SCRIPT_DIR/ZeroG/Resources" ]; then
    cp -R "$SCRIPT_DIR/ZeroG/Resources/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# 6. Copy the SPM resource bundle if it exists
RESOURCE_BUNDLE=$(find "$SCRIPT_DIR/.build/release/" -name "ZeroG_ZeroG.bundle" -type d 2>/dev/null | head -1)
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  📎 Copied resource bundle"
fi

# 7. Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 8. Code signing (skipped if ZEROG_SIGN_IDENTITY is unset)
if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 Signing with: $SIGN_IDENTITY"

    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "❌ Entitlements file not found at $ENTITLEMENTS"
        exit 1
    fi

    # The app has a single Mach-O (the main binary; WhisperKit is statically
    # linked). SPM resource bundles (ZeroG_ZeroG.bundle) hold no code and are
    # sealed into the app signature, so we sign the app bundle in one pass.
    # Hardened runtime (--options runtime) and a secure timestamp are both
    # required for notarization.
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"

    echo "  🔎 Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "  ✅ Signed."
else
    echo "ℹ️  Unsigned build (set ZEROG_SIGN_IDENTITY to sign). Gatekeeper will"
    echo "    quarantine this build on other Macs — fine for local development."
fi

# 9. Notarization (skipped if ZEROG_NOTARY_PROFILE is unset)
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "📜 Notarizing (profile: $NOTARY_PROFILE)…"
    ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

    # notarytool requires a zip; ditto --keepParent preserves the .app wrapper.
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "  📎 Stapling ticket…"
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    rm -f "$ZIP_PATH"
    echo "  ✅ Notarized and stapled — ready for public distribution."
elif [ -n "$SIGN_IDENTITY" ]; then
    echo "ℹ️  Signed but not notarized (set ZEROG_NOTARY_PROFILE to notarize)."
fi

echo ""
echo "✅ $APP_NAME.app built successfully!"
echo "📍 Location: $APP_BUNDLE"
echo ""
echo "To launch:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install (copy to Applications):"
echo "  cp -R $APP_BUNDLE /Applications/"
echo ""
echo "⚠️  First launch: macOS will ask for permissions."
echo "   Grant 'ZeroG' access in:"
echo "   • System Settings → Privacy & Security → Input Monitoring"
echo "   • System Settings → Privacy & Security → Accessibility"
echo "   • System Settings → Privacy & Security → Microphone"
