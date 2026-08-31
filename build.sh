#!/usr/bin/env bash
#
# Builds the native Swift menu-bar app and stages it into RedMagic Cooler.app.
#
# Usage:  ./build.sh [--run]
#           --run   relaunch the app bundle once the build succeeds
#
# Sources are discovered by globbing src-swift, so adding a file needs no edit
# here. The bundle is ad-hoc signed because CoreBluetooth refuses to hand out
# the Bluetooth entitlement to an unsigned binary.

set -euo pipefail

cd "$(dirname "$0")"

APP="RedMagic Cooler.app"
BUNDLE_ID="com.redmagic.cooler"
VERSION="2.1"
BUILD="4"

# ── 1. Compile ────────────────────────────────────────────────────────────────
# main.swift must come last: swiftc treats the final file as the entry point
# when top-level code is present.
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done \
    < <(find src-swift -name '*.swift' ! -name 'main.swift' | sort)
SOURCES+=("src-swift/App/main.swift")

echo "==> Compiling ${#SOURCES[@]} Swift files"
swiftc -O -whole-module-optimization \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework Foundation \
  -framework AppKit \
  -framework CoreBluetooth \
  -framework IOKit \
  -o applet_bin \
  "${SOURCES[@]}"

# ── 2. Stage the bundle ───────────────────────────────────────────────────────
echo "==> Staging $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv applet_bin "$APP/Contents/MacOS/applet"
chmod +x "$APP/Contents/MacOS/applet"

# Regenerate with tools/make-icon.sh if the mark ever changes.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>applet</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>RedMagic Cooler</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSRequiresAquaSystemAppearance</key>
	<true/>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>This app needs Bluetooth to connect to and control the REDMAGIC Cooler 6 Pro.</string>
</dict>
</plist>
PLIST

# ── 3. Sign ───────────────────────────────────────────────────────────────────
# Ad-hoc signature; keeps the Bluetooth permission grant stable across rebuilds.
echo "==> Signing"
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "==> Built $APP ($VERSION build $BUILD)"

if [[ "${1:-}" == "--run" ]]; then
    echo "==> Relaunching"
    open "$APP"
fi
