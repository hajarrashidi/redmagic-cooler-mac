#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the app's own vector logo.
# Only needs re-running if the mark or the icon layout changes.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(mktemp -d)/make-icon"
swiftc -O -sdk "$(xcrun --show-sdk-path)" -framework AppKit \
    -o "$BIN" tools/make-icon/main.swift src-swift/UI/RedMagicLogo.swift
"$BIN" Resources/AppIcon.icns
