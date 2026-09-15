#!/bin/zsh
# Builds MouseDragFix.app into build/ and signs it. Usage: ./build.sh [--install]
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
codesign --force --sign "${IDENTITY:--}" "$BUNDLE"
echo "built $BUNDLE (signed as ${IDENTITY:-ad-hoc})"
if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP" 2>/dev/null || true
    rm -rf "/Applications/$APP.app"
    cp -R "$BUNDLE" /Applications/
    open "/Applications/$APP.app"
    echo "installed and launched /Applications/$APP.app"
fi
