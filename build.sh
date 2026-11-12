#!/usr/bin/env bash
#
# Builds the native Swift menu-bar app and stages it into RedMagic Cooler.app.
#
# Usage:  ./build.sh [--run] [--with-probes]
#           --run           relaunch the app bundle once the build succeeds
#           --with-probes   include the developer protocol-probe transport
#
# Sources are discovered by globbing src-swift, so adding a file needs no edit
# here. The bundle is ad-hoc signed because CoreBluetooth refuses to hand out
# the Bluetooth entitlement to an unsigned binary.

set -euo pipefail

cd "$(dirname "$0")"

APP="Smart Cooler Control.app"
BUNDLE_ID="com.smartcooler.mac"
VERSION="3.1"
BUILD="20"

RUN_AFTER_BUILD=false
WITH_PROBES=false
for argument in "$@"; do
    case "$argument" in
        --run) RUN_AFTER_BUILD=true ;;
        --with-probes) WITH_PROBES=true ;;
        *)
            echo "Unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

# ── 1. Compile ────────────────────────────────────────────────────────────────
# main.swift must come last: swiftc treats the final file as the entry point
# when top-level code is present.
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done \
    < <(find src-swift -name '*.swift' ! -name 'main.swift' | sort)
SWIFT_DEFINES=("-D" "REDMAGIC_APP")
if [[ "$WITH_PROBES" == true ]]; then
    SOURCES+=("tools/probe/ProbeBridge.swift")
    SWIFT_DEFINES+=("-D" "REDMAGIC_PROBES")
fi
SOURCES+=("src-swift/App/main.swift")

echo "==> Compiling ${#SOURCES[@]} Swift files"
swiftc -O -whole-module-optimization \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework Foundation \
  -framework AppKit \
  -framework CoreBluetooth \
  -framework IOKit \
  "${SWIFT_DEFINES[@]}" \
  -o applet_bin \
  "${SOURCES[@]}"

# ── 2. Stage the bundle ───────────────────────────────────────────────────────
echo "==> Staging $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv applet_bin "$APP/Contents/MacOS/applet"
chmod +x "$APP/Contents/MacOS/applet"

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
	<string>Smart Cooler Control</string>
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
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Smart Cooler Control needs Bluetooth to connect to and control supported high-power coolers.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>Smart Cooler Control needs Bluetooth to connect to and control supported high-power coolers.</string>
</dict>
</plist>
PLIST

# ── 3. Sign ───────────────────────────────────────────────────────────────────
# Ad-hoc signature with stable designated requirement; keeps the Bluetooth permission grant stable across rebuilds.
echo "==> Signing"
codesign --force --deep --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP" 2>/dev/null

echo "==> Installing to /Applications/$APP"
rm -rf "/Applications/$APP"
cp -R "$APP" "/Applications/$APP"
# Remove duplicate in source folder so Spotlight / App Switcher only see the canonical app
rm -rf "$APP"

# Update LaunchServices registration
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP" 2>/dev/null || true

echo "==> Built and installed /Applications/$APP ($VERSION build $BUILD)"

if [[ "$RUN_AFTER_BUILD" == true ]]; then
    echo "==> Relaunching"
    nohup "/Applications/$APP/Contents/MacOS/applet" >/dev/null 2>&1 &
fi
