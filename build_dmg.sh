#!/bin/bash
# ─────────────────────────────────────────────────────────────
# LiteSSH — build release app bundle and package as DMG
#
# Usage:
#   chmod +x build_dmg.sh
#   ./build_dmg.sh
#
# Outputs:
#   LiteSSH.app        — runnable app bundle (also left on disk for quick testing)
#   LiteSSH-1.0.dmg    — drag-to-Applications installer
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LiteSSH"
BUNDLE_ID="com.kai.litessh"
VERSION="1.0"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
BUILD_CACHE="$SCRIPT_DIR/.build"

# ── Colours ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'
step()  { echo -e "${BLUE}▶ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
die()   { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo ""
echo -e "${BOLD}  LiteSSH — Release Build${NC}"
echo "  ───────────────────────────────"

# ── 1. Build Swift package ────────────────────────────────────
step "Compiling (swift build -c release)…"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | grep -E "^(error:|warning:|Build complete)" || true

# Binary can be under native arch or universal path
BINARY=$(find "$BUILD_CACHE" -name "$APP_NAME" -type f \
         | grep -E "/release/$APP_NAME$" | head -1)
[[ -z "$BINARY" ]] && die "Binary not found — did the build succeed?"
ok "Binary: $BINARY"

# ── 2. Create .app bundle structure ──────────────────────────
step "Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist — LSUIElement is intentionally absent so the app
# shows in the Dock.  NSApp.setActivationPolicy(.regular) in
# AppDelegate also ensures this at runtime.
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
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

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <!-- Retina / high-DPI support -->
    <key>NSHighResolutionCapable</key>
    <true/>

    <!-- Required for SwiftUI App lifecycle on macOS -->
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>NSHumanReadableCopyright</key>
    <string>© 2026 LiteSSH</string>
</dict>
</plist>
PLIST
ok "Bundle created"

# ── 3. Generate & install app icon ───────────────────────────
step "Generating app icon…"

TMP_PNG="$BUILD_CACHE/icon_1024.png"
mkdir -p "$BUILD_CACHE"

# Draw the 1024×1024 master PNG via generate_icon.swift
swift "$SCRIPT_DIR/generate_icon.swift" "$TMP_PNG"

# Build iconset with all required sizes
ICONSET="$BUILD_CACHE/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

for PT in 16 32 128 256 512; do
    PX=$(( PT ))
    PX2=$(( PT * 2 ))
    sips -z $PX $PX   "$TMP_PNG" --out "$ICONSET/icon_${PT}x${PT}.png"      > /dev/null
    sips -z $PX2 $PX2 "$TMP_PNG" --out "$ICONSET/icon_${PT}x${PT}@2x.png"  > /dev/null
done

iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$TMP_PNG"
ok "Icon: AppIcon.icns"

# ── 4. Ad-hoc code signing ───────────────────────────────────
# A proper Developer ID signature lets you distribute to others without
# Gatekeeper warnings.  Ad-hoc (-) works fine for personal / local use.
step "Signing (ad-hoc)…"
if codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null; then
    ok "Signed (ad-hoc)"
else
    warn "codesign failed — continuing anyway (app should still run locally)"
fi

# ── 5. Quick smoke-test ───────────────────────────────────────
step "Verifying bundle…"
EXEC="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PLIST_CHECK="$APP_BUNDLE/Contents/Info.plist"
ICNS_CHECK="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
[[ -x "$EXEC" ]]         || die "Executable missing or not executable"
[[ -f "$PLIST_CHECK" ]]  || die "Info.plist missing"
[[ -f "$ICNS_CHECK" ]]   || die "AppIcon.icns missing"
ok "Bundle looks good"

# ── 6. Package as DMG ────────────────────────────────────────
step "Creating $DMG_NAME…"
TMP_DIR=$(mktemp -d)
cp -r "$APP_BUNDLE" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

rm -f "$SCRIPT_DIR/$DMG_NAME"
hdiutil create \
    -srcfolder "$TMP_DIR" \
    -volname   "$APP_NAME" \
    -fs        HFS+ \
    -format    UDZO \
    -imagekey  zlib-level=9 \
    -o         "$SCRIPT_DIR/$APP_NAME-$VERSION" > /dev/null
rm -rf "$TMP_DIR"
ok "DMG: $SCRIPT_DIR/$DMG_NAME"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ✓ Done!${NC}"
echo ""
echo "  Installer : $DMG_NAME"
echo "  App bundle: $APP_NAME.app  (kept here for quick double-click testing)"
echo ""
echo "  To install:"
echo "    open \"$SCRIPT_DIR/$DMG_NAME\""
echo "    … then drag LiteSSH → Applications"
echo ""
echo "  To run without installing:"
echo "    open \"$APP_BUNDLE\""
echo ""
