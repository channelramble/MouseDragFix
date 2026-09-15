#!/bin/zsh
# Builds MouseDragFix.app into build/ and signs it. Usage: ./build.sh [--install | --release]
set -euo pipefail
cd "$(dirname "$0")"
APP=MouseDragFix
BUNDLE="build/$APP.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
# Xcode's swiftc refuses to run until its license is accepted; fall back to the Command Line Tools.
if ! swiftc --version >/dev/null 2>&1; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    -framework Cocoa -framework SwiftUI -framework ServiceManagement -framework Carbon \
    Sources/*.swift -o "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"' || true)
codesign --force --options runtime --timestamp --sign "${IDENTITY:--}" "$BUNDLE" 2>/dev/null \
    || codesign --force --options runtime --sign "${IDENTITY:--}" "$BUNDLE"   # no timestamp server offline
echo "built $BUNDLE (signed as ${IDENTITY:-ad-hoc}, hardened runtime)"
if [[ "${1:-}" == "--release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUNDLE/Contents/Info.plist")
    ZIP="build/$APP-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$BUNDLE" "$ZIP"
    codesign --verify --deep --strict "$BUNDLE" && spctl --assess --type execute "$BUNDLE" 2>&1 | sed 's/^/gatekeeper: /' || true
    echo "release archive: $ZIP ($(du -h "$ZIP" | cut -f1))"
fi
if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP" 2>/dev/null || true
    rm -rf "/Applications/$APP.app"
    cp -R "$BUNDLE" /Applications/
    open "/Applications/$APP.app"
    echo "installed and launched /Applications/$APP.app"
fi
