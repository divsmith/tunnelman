#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="TunnelMan"
BUNDLE_ID="com.tunnelman.app"
VERSION="1.0.0"
OUTPUT_DIR="output"
BUNDLE_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# ── Build ────────────────────────────────────────────────────────────────────
echo "▸ Building ${APP_NAME} (release)…"
swift build -c release 2>&1

BINARY=".build/release/${APP_NAME}"
if [ ! -f "${BINARY}" ]; then
    echo "✗ Build failed — binary not found at ${BINARY}" >&2
    exit 1
fi

# Locate the SwiftPM resource bundle (contains terminal.html)
RESOURCE_BUNDLE=$(find .build -path "*/release/TunnelMan_TunnelManServer.bundle" -type d | head -1)
if [ -z "${RESOURCE_BUNDLE}" ]; then
    echo "✗ Resource bundle not found in .build/" >&2
    exit 1
fi

# ── Create .app bundle ───────────────────────────────────────────────────────
echo "▸ Creating ${APP_NAME}.app bundle…"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BINARY}" "${MACOS_DIR}/${APP_NAME}"

# SwiftPM's auto-generated Bundle.module accessor looks for the resource bundle
# at Bundle.main.bundleURL (the .app root), not Contents/Resources/.
cp -R "${RESOURCE_BUNDLE}" "${BUNDLE_DIR}/TunnelMan_TunnelManServer.bundle"

# ── Info.plist ───────────────────────────────────────────────────────────────
cat > "${CONTENTS_DIR}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# ── Done ─────────────────────────────────────────────────────────────────────
APP_SIZE=$(du -sh "${BUNDLE_DIR}" | cut -f1)
echo ""
echo "✔ ${BUNDLE_DIR} (${APP_SIZE})"
echo ""
echo "  Run:  open ${BUNDLE_DIR}"
echo "  Or:   ${MACOS_DIR}/${APP_NAME}"
