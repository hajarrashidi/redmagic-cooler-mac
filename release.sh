#!/usr/bin/env bash
#
# Builds a distributable DMG.
#
# Usage:  ./release.sh [version]
#           version   defaults to the CFBundleShortVersionString in build.sh
#
# Signing depends on what's in your environment:
#
#   Nothing set                 ad-hoc signature. Free, but Gatekeeper refuses
#                               to open the downloaded app at all on current
#                               macOS — users must strip the quarantine flag by
#                               hand (see "Install" in the README).
#
#   DEVELOPER_ID set            signs with your Developer ID Application cert.
#                               Requires a paid Apple Developer account.
#
#   DEVELOPER_ID + NOTARY_*     also submits to Apple's notary service and
#                               staples the ticket, so the DMG opens with no
#                               warning at all. This is the clean experience.
#
# Example:
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_KEYCHAIN_PROFILE="notary"   # from: xcrun notarytool store-credentials
#   ./release.sh 2.0

set -euo pipefail
cd "$(dirname "$0")"

APP="RedMagic Cooler.app"
VOLUME="RedMagic Cooler"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ── 1. Build ──────────────────────────────────────────────────────────────────
./build.sh

# Read the version *after* building, or the DMG would be named for whatever
# stale bundle was lying around from a previous build.
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist" 2>/dev/null || echo dev)}"
DMG="dist/RedMagic-Cooler-${VERSION}.dmg"

# ── 2. Sign ───────────────────────────────────────────────────────────────────
# The hardened runtime is required for notarization. It's harmless without it.
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "==> Signing with Developer ID"
    codesign --force --deep --timestamp --options runtime \
        --sign "$DEVELOPER_ID" "$APP"
else
    echo "==> No DEVELOPER_ID set; keeping the ad-hoc signature"
    echo "    Downloads will be blocked by Gatekeeper until the user removes"
    echo "    the quarantine flag — see the Install section of the README."
fi

# ── 3. Lay out the disk image ─────────────────────────────────────────────────
echo "==> Building $DMG"
mkdir -p dist
rm -f "$DMG"

cp -R "$APP" "$STAGE/"
# The conventional drag-to-install target.
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    -quiet \
    "$DMG"

# ── 4. Notarize ───────────────────────────────────────────────────────────────
if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "==> Signing the disk image"
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

    echo "==> Submitting to Apple's notary service (this takes a few minutes)"
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait

    echo "==> Stapling the ticket"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
else
    echo "==> Skipping notarization (needs DEVELOPER_ID and NOTARY_KEYCHAIN_PROFILE)"
fi

echo
echo "==> $DMG  ($(du -h "$DMG" | cut -f1))"
echo "    Attach it to a release with:"
echo "      gh release create v${VERSION} \"$DMG\" --generate-notes"
