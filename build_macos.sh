#!/bin/bash
# ==============================================================================
# Madarsa Management System - macOS Automated Build Script (.app & .dmg)
# Works on both Apple Silicon (M1/M2/M3/M4) and Intel Macs
# ==============================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}   Madarsa Management System - macOS Build (.app & .dmg)   ${NC}"
echo -e "${BLUE}==========================================================${NC}"

# Navigate to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 1. Check if Flutter is installed
echo -e "\n${YELLOW}[1/4] Checking Flutter installation...${NC}"
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter SDK not found in PATH!${NC}"
    echo -e "Please install Flutter from https://docs.flutter.dev/get-started/install/macos"
    exit 1
fi
echo -e "${GREEN}✓ Flutter found: $(flutter --version | head -n 1)${NC}"

# 2. Check Xcode Command Line Tools
echo -e "\n${YELLOW}[2/4] Checking Xcode tools...${NC}"
if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ Xcode command line tools not found! Installing...${NC}"
    xcode-select --install
    exit 1
fi
echo -e "${GREEN}✓ Xcode tools verified.${NC}"

# 3. Get dependencies and build macOS release
echo -e "\n${YELLOW}[3/4] Building macOS Release (.app bundle)...${NC}"
flutter pub get
flutter build macos --release --no-tree-shake-icons

APP_SRC="build/macos/Build/Products/Release/madarsa_app.app"

if [ ! -d "$APP_SRC" ]; then
    echo -e "${RED}❌ Build failed! App bundle not found at: $APP_SRC${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Native macOS .app built successfully!${NC}"

# 4. Packaging into .dmg installer
echo -e "\n${YELLOW}[4/4] Creating .dmg Installer...${NC}"
DMG_NAME="Madarsa_App_v0.0.0.3_macOS.dmg"
TEMP_DMG_DIR="build/dmg_temp"

rm -rf "$TEMP_DMG_DIR" "$DMG_NAME"
mkdir -p "$TEMP_DMG_DIR"

# Copy .app into DMG staging directory
cp -R "$APP_SRC" "$TEMP_DMG_DIR/Madarsa Management.app"

# Create symlink to /Applications for easy drag-and-drop installation
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Create disk image
hdiutil create \
    -volname "Madarsa Management System" \
    -srcfolder "$TEMP_DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

rm -rf "$TEMP_DMG_DIR"

echo -e "\n${GREEN}==========================================================${NC}"
echo -e "${GREEN}🎉 SUCCESS! macOS Build Completed Successfully!${NC}"
echo -e "1. Native App Bundle : $SCRIPT_DIR/$APP_SRC"
echo -e "2. Single DMG Setup  : $SCRIPT_DIR/$DMG_NAME"
echo -e "${GREEN}==========================================================${NC}"

# Reveal in Finder
if command -v open &> /dev/null; then
    open -R "$DMG_NAME"
fi
