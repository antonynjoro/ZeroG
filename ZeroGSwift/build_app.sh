#!/bin/bash
# build_app.sh — Build ZeroG as a macOS .app bundle
# Usage: ./build_app.sh
# Output: ./build/ZeroG.app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ZeroG"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

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
