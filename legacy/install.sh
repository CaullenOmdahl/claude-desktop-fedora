#!/bin/bash
set -e

# Claude Desktop for Linux - Leap-Pad Installer
# This minimal script always fetches the latest installer from GitHub
# Eliminates all caching issues by directly executing the main installer

REPO_URL="https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}ℹ${NC} Claude Desktop Leap-Pad Installer - Fetching latest installer..."

# Always fetch and execute the main installer directly from GitHub
# Add timestamp for absolute cache-busting
TIMESTAMP=$(date +%s%N)  # Nanosecond precision for maximum uniqueness
MAIN_INSTALLER_URL="${REPO_URL}/install-main.sh?t=${TIMESTAMP}"

echo -e "${BLUE}ℹ${NC} Downloading and executing main installer from GitHub..."

# Fetch and execute in one step to avoid any local caching
# Use aggressive cache-busting headers to bypass GitHub CDN cache
if curl -fsSL \
    -H "Cache-Control: no-cache, no-store, must-revalidate" \
    -H "Pragma: no-cache" \
    -H "Expires: 0" \
    "$MAIN_INSTALLER_URL" | bash; then
    echo -e "${GREEN}✓${NC} Installation completed successfully!"
else
    echo -e "${RED}❌${NC} Installation failed"
    exit 1
fi