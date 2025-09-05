#!/bin/bash
set -e

# Cleanup function to remove temporary files on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "🧹 Cleaning up temporary files after successful installation..."
    else
        log_error "🧹 Cleaning up temporary files after failed installation..."
    fi

    # Remove Claude-related temporary files
    sudo rm -rf /tmp/build /tmp/build-fedora.sh /tmp/VERSION /tmp/scripts /tmp/Claude-* /tmp/install_new.sh /tmp/electron* 2>/dev/null || true

    if [ $exit_code -eq 0 ]; then
        log_success "Cleanup completed"
    else
        log_info "Cleanup completed (installation failed with exit code $exit_code)"
    fi
}

# Set up cleanup trap for both successful exit and failures
trap cleanup EXIT

# Claude Desktop for Linux - Universal Installer
# This script builds and installs Claude Desktop from the official Windows installer
# Note: Users build from Anthropic's official installer - no redistribution of binaries

SCRIPT_VERSION="2.0.2"
REPO_URL="https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main"
INSTALL_MARKER="/usr/lib64/claude-desktop/.installed_version"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

# Estimated time tracker
log_with_time() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    case "$level" in
        "info") echo -e "${BLUE}ℹ${NC} [$timestamp] $message" ;;
        "success") echo -e "${GREEN}✓${NC} [$timestamp] $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} [$timestamp] $message" ;;
        "error") echo -e "${RED}❌${NC} [$timestamp] $message" ;;
    esac
}

check_system() {
    if [ ! -f "/etc/fedora-release" ] && ! grep -qi "fedora" /etc/os-release 2>/dev/null; then
        log_error "This installer requires a Fedora-based Linux distribution"
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        log_error "Please run with sudo to install system packages"
        exit 1
    fi

    log_success "System compatibility verified"
}

get_installed_version() {
    if [ -f "$INSTALL_MARKER" ]; then
        cat "$INSTALL_MARKER" 2>/dev/null || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_latest_claude_version() {
    log_info "Checking latest Claude Desktop version..."

    # Download and check the installer to get version
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    log_info "📥 Downloading Claude installer to check version (120MB)..."
    if ! curl --progress-bar -o Claude-Setup-x64.exe "https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"; then
        log_error "Failed to download Claude Desktop installer"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    log_success "Download completed"

    # Install 7zip if needed
    if ! command -v 7z &> /dev/null; then
        log_info "Installing p7zip for extraction..."
        dnf install -y p7zip-plugins >/dev/null 2>&1
        log_success "p7zip installed"
    fi

    # Extract and get version
    log_info "🔍 Extracting installer to detect version..."
    if ! 7z x -y Claude-Setup-x64.exe >/dev/null 2>&1; then
        log_error "Failed to extract installer"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    NUPKG_FILE=$(find . -name "AnthropicClaude-*-full.nupkg" | head -1)

    if [ -z "$NUPKG_FILE" ]; then
        log_error "Could not determine Claude Desktop version"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    VERSION=$(echo "$NUPKG_FILE" | grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full\.nupkg)')
    log_success "Detected Claude Desktop version: $VERSION"

    # Cleanup
    rm -rf "$TEMP_DIR"
    echo "$VERSION"
}

update_script() {
    # Skip update check - leap-pad architecture ensures we're always running latest
    log_success "Running latest installer via leap-pad architecture"
}

download_build_script() {
    log_info "Downloading latest build script and VERSION file..."

    # Remove any cached files to ensure fresh download
    rm -f /tmp/build-fedora.sh /tmp/VERSION

    # Add cache-busting timestamp to URLs
    TIMESTAMP=$(date +%s)
    if ! curl -s -o /tmp/build-fedora.sh "$REPO_URL/build-fedora.sh?t=$TIMESTAMP"; then
        log_error "Failed to download build script"
        exit 1
    fi

    # Download VERSION file to same location
    if ! curl -s -o /tmp/VERSION "$REPO_URL/VERSION?t=$TIMESTAMP"; then
        log_error "Failed to download VERSION file"
        exit 1
    fi

    chmod +x /tmp/build-fedora.sh
    # Download optimization scripts
    mkdir -p /tmp/scripts
    log_info "Downloading performance optimization scripts..."

    if curl -s -o /tmp/scripts/environment-detector.sh "$REPO_URL/scripts/environment-detector.sh?t=$TIMESTAMP"; then
        log_success "Environment detector downloaded"
    else
        log_warning "Environment detector download failed, will use fallback"
    fi

    if curl -s -o /tmp/scripts/electron-args-builder.sh "$REPO_URL/scripts/electron-args-builder.sh?t=$TIMESTAMP"; then
        log_success "Electron args builder downloaded"
    else
        log_warning "Electron args builder download failed, will use fallback"
    fi

    chmod +x /tmp/scripts/*.sh 2>/dev/null
    log_success "Build script, VERSION file, and optimization scripts downloaded"
}

build_and_install() {
    CLAUDE_VERSION="$1"  # Pass Claude version to avoid re-downloading
    log_info "🔨 Building Claude Desktop from official installer..."

    # Run the build script
    cd /tmp
    BUILD_START=$(date +%s)
    log_with_time "info" "⚙️ Starting build process (estimated 2-5 minutes depending on system speed)..."
    if ! ./build-fedora.sh; then
        log_error "Build failed"
        exit 1
    fi
    BUILD_ELAPSED=$(($(date +%s) - BUILD_START))
    log_with_time "success" "Build completed successfully in ${BUILD_ELAPSED}s!"

    # Find the built RPM
    log_info "📦 Locating built RPM package..."
    RPM_FILE=$(find . -name "claude-desktop-*.rpm" | head -1)
    if [ -z "$RPM_FILE" ]; then
        log_error "Built RPM not found"
        exit 1
    fi

    log_info "Installing Claude Desktop RPM..."
    if dnf install -y "$RPM_FILE" 2>/dev/null; then
        # Get package version from build
        PACKAGE_VERSION=$(cat /tmp/VERSION 2>/dev/null || echo "1.0.0")

        # Mark installation
        echo "${PACKAGE_VERSION}-${CLAUDE_VERSION}" > "$INSTALL_MARKER"

        log_success "Claude Desktop installed successfully!"
        log_success "📦 Package version: $PACKAGE_VERSION (Claude $CLAUDE_VERSION)"
    else
        log_error "Installation failed"
        exit 1
    fi

    # Note: Cleanup is handled by EXIT trap
}

create_update_checker() {
    log_info "Setting up automatic update checking..."

    # Create update checker script
    cat > /usr/local/bin/claude-desktop-update-check << 'EOF'
#!/bin/bash

REPO_URL="https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main"
INSTALL_MARKER="/usr/lib64/claude-desktop/.installed_version"

check_for_updates() {
    if [ -f "$INSTALL_MARKER" ]; then
        INSTALLED_VERSION=$(cat "$INSTALL_MARKER")

        # Check for Claude Desktop updates (simplified check)
        TEMP_FILE=$(mktemp)
        if curl -s -o "$TEMP_FILE" "$REPO_URL/install.sh"; then
            echo "Update check completed. Run 'sudo claude-desktop-installer' to update if needed."
        fi
        rm -f "$TEMP_FILE"
    fi
}

# Only check if not checked in last 24 hours
LAST_CHECK="/tmp/.claude_update_check"
if [ ! -f "$LAST_CHECK" ] || [ $(find "$LAST_CHECK" -mtime +1 2>/dev/null | wc -l) -gt 0 ]; then
    check_for_updates
    touch "$LAST_CHECK"
fi
EOF

    chmod +x /usr/local/bin/claude-desktop-update-check

    # Update the launcher to include update check
    if [ -f /usr/bin/claude-desktop ]; then
        # Backup original launcher
        cp /usr/bin/claude-desktop /usr/bin/claude-desktop.backup

        # Create new launcher with update check
        cat > /usr/bin/claude-desktop << 'EOF'
#!/bin/bash

# Check for updates (non-blocking)
/usr/local/bin/claude-desktop-update-check &

# Optimized launcher with dynamic backend selection
LOG_FILE="$HOME/claude-desktop-launcher.log"

# Performance optimization scripts path
SCRIPTS_DIR="/usr/lib64/claude-desktop/scripts"

# Source optimization scripts if available
if [ -f "$SCRIPTS_DIR/environment-detector.sh" ]; then
    source "$SCRIPTS_DIR/environment-detector.sh"
    export_optimal_backend
else
    export GDK_BACKEND=x11
    echo "Using fallback X11 backend" >&2
fi

if [ -f "$SCRIPTS_DIR/electron-args-builder.sh" ]; then
    source "$SCRIPTS_DIR/electron-args-builder.sh"
    export_electron_args
else
    export ELECTRON_ARGS="--ozone-platform-hint=auto --enable-logging=file --log-level=INFO --disable-gpu-sandbox --no-sandbox"
    echo "Using fallback Electron arguments" >&2
fi

# Backend-specific optimizations
if [ "$GDK_BACKEND" = "wayland" ]; then
    export GTK_USE_PORTAL=1
    export QT_QPA_PLATFORM=wayland
    export MOZ_ENABLE_WAYLAND=1
else
    export GTK_USE_PORTAL=0
    export QT_QPA_PLATFORM=xcb
fi

export ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Debug mode support
if [ "$CLAUDE_DEBUG" = "1" ]; then
    echo "=== Claude Desktop Debug Mode ===" >&2
    [ -f "$SCRIPTS_DIR/environment-detector.sh" ] && debug_environment
    [ -f "$SCRIPTS_DIR/electron-args-builder.sh" ] && debug_electron_config
    echo "============================" >&2
fi

# Launch with optimized configuration
/usr/lib64/claude-desktop/electron/electron /usr/lib64/claude-desktop/app.asar $ELECTRON_ARGS --log-file="$LOG_FILE" "$@"
EOF
        chmod +x /usr/bin/claude-desktop
    fi

    log_success "Update checking enabled"
}

create_installer_alias() {
    # Create a convenient installer alias
    cat > /usr/local/bin/claude-desktop-installer << EOF
#!/bin/bash
# Claude Desktop Installer/Updater
curl -sSL $REPO_URL/install.sh | sudo bash
EOF
    chmod +x /usr/local/bin/claude-desktop-installer
    log_success "Created 'claude-desktop-installer' command for future updates"
}

main() {
    echo
    log_info "Claude Desktop for Linux Installer v$SCRIPT_VERSION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    check_system

    log_info "🔍 Checking current installation status..."
    INSTALLED_VERSION=$(get_installed_version)

    START_TIME=$(date +%s)
    log_with_time "info" "🌐 Checking for latest Claude Desktop version (downloading 120MB installer)..."
    LATEST_CLAUDE=$(get_latest_claude_version)
    ELAPSED=$(($(date +%s) - START_TIME))
    log_with_time "success" "Version check completed in ${ELAPSED}s"

    if [ "$INSTALLED_VERSION" != "not_installed" ]; then
        log_info "Currently installed: $INSTALLED_VERSION"
        log_info "Latest Claude Desktop: $LATEST_CLAUDE"

        if [[ "$INSTALLED_VERSION" == *"$LATEST_CLAUDE"* ]]; then
            log_success "Claude Desktop is up to date!"
            read -p "Reinstall anyway? (y/N): " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
        else
            log_warning "Update available"
        fi
    else
        log_info "Installing Claude Desktop $LATEST_CLAUDE"
    fi

    update_script
    download_build_script
    build_and_install "$LATEST_CLAUDE"
    create_update_checker
    create_installer_alias

    echo
    log_success "Installation complete!"
    echo
    echo "📱 Launch: claude-desktop"
    echo "🔄 Update: claude-desktop-installer"
    echo "📍 MCP Config: ~/.config/Claude/claude_desktop_config.json"
    echo
}

# Handle command line arguments
case "${1:-}" in
    --version|-v)
        echo "Claude Desktop Installer v$SCRIPT_VERSION"
        exit 0
        ;;
    --help|-h)
        echo "Claude Desktop for Linux Installer"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --version, -v    Show version"
        echo "  --help, -h       Show this help"
        echo
        echo "This script downloads and builds Claude Desktop from Anthropic's"
        echo "official installer. No pre-built binaries are distributed."
        exit 0
        ;;
esac

main "$@"
