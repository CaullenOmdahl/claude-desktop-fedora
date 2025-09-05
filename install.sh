#!/bin/bash
# Claude Desktop Fedora Installer - Unified Single-File Version
# One-line install: curl -sSL https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install-unified.sh | sudo bash

set -eE

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly INSTALLER_VERSION="3.1.0"
readonly ELECTRON_VERSION="37.0.0"
readonly BUILD_DIR="/tmp/claude-desktop-build-$$"
readonly CLAUDE_URL="https://storage.googleapis.com/app-content-distribution/electron-builds/claude/Claude%20Setup%20${CLAUDE_VERSION:-0.12.129}.exe"

# Logging functions
log_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_info "Cleaning up after failure..."
    fi
    rm -rf "$BUILD_DIR"
    exit $exit_code
}
trap cleanup EXIT

# Print banner
print_banner() {
    echo
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Claude Desktop Installer for Fedora v$INSTALLER_VERSION        ║${NC}"
    echo -e "${BLUE}║              Intelligent Linux Desktop Integration           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This installer must be run as root. Use: sudo $0"
        exit 1
    fi
}

# Detect system
check_system() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_warn "This installer is designed for Fedora Linux"
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        log_error "Only x86_64 architecture is supported"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Checking dependencies..."

    local deps=(
        "sqlite3"
        "p7zip p7zip-plugins"
        "wget"
        "icoutils"
        "ImageMagick"
        "nodejs npm"
        "rpm-build"
        "libnotify"
    )

    local missing=()
    for dep in "${deps[@]}"; do
        local pkg="${dep%% *}"
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        dnf install -y ${missing[@]} || {
            log_error "Failed to install dependencies"
            exit 1
        }
    fi

    log_success "All dependencies installed"
}

# Setup Node/NPM
setup_node() {
    # Check for npx
    if ! command -v npx &>/dev/null; then
        # Check for NVM
        if [[ -n "$SUDO_USER" ]]; then
            local nvm_dir="/home/$SUDO_USER/.nvm"
            if [[ -s "$nvm_dir/nvm.sh" ]]; then
                export NVM_DIR="$nvm_dir"
                source "$nvm_dir/nvm.sh"
                local node_path="$(command -v node 2>/dev/null)"
                if [[ -n "$node_path" ]]; then
                    export PATH="$(dirname "$node_path"):$PATH"
                    log_info "Using NVM Node.js installation"
                fi
            fi
        fi

        # Final check
        if ! command -v npx &>/dev/null; then
            log_error "npx not found. Installing Node.js..."
            dnf install -y nodejs npm
        fi
    fi
}

# Download Electron
download_electron() {
    local electron_url="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"
    local electron_zip="$BUILD_DIR/electron.zip"

    log_info "Downloading Electron v${ELECTRON_VERSION}..."
    wget -q --show-progress "$electron_url" -O "$electron_zip" || {
        log_error "Failed to download Electron"
        exit 1
    }

    log_info "Extracting Electron..."
    mkdir -p "$BUILD_DIR/electron"
    unzip -q "$electron_zip" -d "$BUILD_DIR/electron"
    rm "$electron_zip"
    log_success "Electron prepared"
}

# Download Claude installer
download_claude() {
    local installer="$BUILD_DIR/Claude-Setup.exe"

    log_info "Downloading Claude Desktop installer..."
    wget -q --show-progress "$CLAUDE_URL" -O "$installer" || {
        log_error "Failed to download Claude Desktop"
        exit 1
    }

    log_info "Extracting resources..."
    cd "$BUILD_DIR"
    7z x -y "$installer" &>/dev/null || {
        log_error "Failed to extract installer"
        exit 1
    }

    # Find and extract the nupkg file
    local nupkg_file=$(find . -name "AnthropicClaude-*-full.nupkg" | head -1)
    if [[ -z "$nupkg_file" ]]; then
        log_error "Could not find Claude package file"
        exit 1
    fi

    unzip -q "$nupkg_file" -d extracted || {
        log_error "Failed to extract Claude package"
        exit 1
    }

    log_success "Claude Desktop extracted"
}

# Process app.asar
process_asar() {
    log_info "Processing application files..."

    cd "$BUILD_DIR"
    cp extracted/lib/net45/resources/app.asar .

    # Extract and modify app.asar
    npx asar extract app.asar app-unpacked

    # Apply window dragging fix
    if [[ -f "app-unpacked/index.html" ]]; then
        sed -i 's/<body>/<body style="-webkit-app-region: no-drag;">/' app-unpacked/index.html
    fi

    # Create native bindings replacement
    cat > "$BUILD_DIR/claude-native.js" << 'EOF'
const os = require('os');
const { app } = require('electron');

// Enhanced keyboard simulation for Linux
const keyMap = {
    'Cmd': 'Meta', 'Command': 'Meta', 'Super': 'Meta', 'Win': 'Meta',
    'Option': 'Alt', 'Control': 'Ctrl', 'Return': 'Enter',
    'Escape': 'Esc', 'Delete': 'Backspace', 'Space': ' '
};

// System detection helpers
function getDesktopEnvironment() {
    const de = process.env.XDG_CURRENT_DESKTOP || process.env.DESKTOP_SESSION || '';
    return de.toLowerCase();
}

function isWayland() {
    return process.env.XDG_SESSION_TYPE === 'wayland' ||
           process.env.WAYLAND_DISPLAY !== undefined;
}

// Window state management
let windowProgress = 0;
let windowUrgent = false;

class ClaudeNative {
    constructor() {
        this.platform = os.platform();
        this.desktopEnvironment = getDesktopEnvironment();
        this.isWayland = isWayland();
    }

    getPlatform() {
        return 'linux';
    }

    openExternal(url) {
        require('child_process').exec(`xdg-open "${url}"`);
    }

    simulateKeyPress(keys) {
        const mapped = keys.map(k => keyMap[k] || k);
        return { keys: mapped, simulated: true };
    }

    setWindowProgress(progress) {
        windowProgress = Math.max(0, Math.min(1, progress));
    }

    setWindowUrgent(urgent) {
        windowUrgent = !!urgent;
    }

    getSystemInfo() {
        return {
            platform: this.platform,
            arch: os.arch(),
            release: os.release(),
            desktop: this.desktopEnvironment,
            wayland: this.isWayland,
            memory: os.totalmem(),
            cpus: os.cpus().length
        };
    }

    showNotification(title, body, options = {}) {
        try {
            const { exec } = require('child_process');
            const escapedTitle = title.replace(/"/g, '\\"');
            const escapedBody = body.replace(/"/g, '\\"');
            exec(`notify-send "${escapedTitle}" "${escapedBody}" --icon=claude-desktop`);
        } catch (error) {
            console.error('Notification error:', error);
        }
    }
}

module.exports = new ClaudeNative();
EOF

    # Replace native bindings
    for binding_path in "app-unpacked/node_modules/claude-native/index.js" \
                       "app-unpacked/node_modules/claude-native.js" \
                       "app-unpacked/claude-native.js"; do
        if [[ -f "$binding_path" ]] || mkdir -p "$(dirname "$binding_path")" 2>/dev/null; then
            cp "$BUILD_DIR/claude-native.js" "$binding_path" 2>/dev/null || true
        fi
    done

    # Repack app.asar
    npx asar pack app-unpacked app.asar
    log_success "Application files processed"
}

# Extract icons
extract_icons() {
    log_info "Extracting icons..."

    cd "$BUILD_DIR"
    if [[ -f "extracted/lib/net45/claude-desktop.ico" ]]; then
        local ico_file="extracted/lib/net45/claude-desktop.ico"
    else
        local ico_file=$(find . -name "*.ico" | head -1)
    fi

    if [[ -n "$ico_file" ]]; then
        # Extract all sizes from ICO
        wrestool -x -t14 "$ico_file" -o . 2>/dev/null || true

        # Convert to PNG at different sizes
        for size in 16 32 48 64 128 256 512; do
            convert "$ico_file" -resize ${size}x${size} -background none "claude-desktop-${size}.png" 2>/dev/null || true
        done

        log_success "Icons extracted"
    else
        log_warn "No icon file found, using default"
    fi
}

# Create RPM package
create_rpm() {
    log_info "Building RPM package..."

    # Setup RPM build tree
    local rpm_root="$BUILD_DIR/rpmbuild"
    mkdir -p "$rpm_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    # Create spec file
    cat > "$rpm_root/SPECS/claude-desktop.spec" << EOF
Name:           claude-desktop
Version:        $INSTALLER_VERSION
Release:        1%{?dist}
Summary:        Claude Desktop for Linux
License:        Proprietary
URL:            https://claude.ai

Requires:       libnotify
AutoReqProv:    no

%description
Claude Desktop application built from official sources with Linux optimizations

%install
mkdir -p %{buildroot}/usr/lib64/claude-desktop
mkdir -p %{buildroot}/usr/lib64/claude-desktop/electron
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/{16x16,32x32,48x48,64x64,128x128,256x256,512x512}/apps

# Copy Electron
cp -r $BUILD_DIR/electron/* %{buildroot}/usr/lib64/claude-desktop/electron/

# Copy app files
cp $BUILD_DIR/app.asar %{buildroot}/usr/lib64/claude-desktop/resources/app.asar

# Copy icons
for size in 16 32 48 64 128 256 512; do
    if [[ -f "$BUILD_DIR/claude-desktop-\${size}.png" ]]; then
        cp "$BUILD_DIR/claude-desktop-\${size}.png" \\
           %{buildroot}/usr/share/icons/hicolor/\${size}x\${size}/apps/claude-desktop.png
    fi
done

# Create launcher script
cat > %{buildroot}/usr/bin/claude-desktop << 'LAUNCHER'
#!/bin/bash
export ELECTRON_IS_DEV=0
export NODE_ENV=production

# Detect display server
if [[ "\$XDG_SESSION_TYPE" == "wayland" ]]; then
    export ELECTRON_OZONE_PLATFORM_HINT=wayland
    FLAGS="--enable-features=UseOzonePlatform --ozone-platform=wayland"
else
    FLAGS=""
fi

# Hardware acceleration
FLAGS="\$FLAGS --enable-gpu-rasterization --enable-zero-copy"

exec /usr/lib64/claude-desktop/electron/electron \\
    /usr/lib64/claude-desktop/resources/app.asar \\
    \$FLAGS "\$@"
LAUNCHER

chmod 755 %{buildroot}/usr/bin/claude-desktop

# Create desktop file
cat > %{buildroot}/usr/share/applications/claude-desktop.desktop << 'DESKTOP'
[Desktop Entry]
Name=Claude
Comment=Claude Desktop Application
Exec=claude-desktop %U
Terminal=false
Type=Application
Icon=claude-desktop
Categories=Development;Office;Chat;
MimeType=x-scheme-handler/claude;
StartupNotify=true
StartupWMClass=Claude
DESKTOP

%files
/usr/lib64/claude-desktop/
/usr/bin/claude-desktop
/usr/share/applications/claude-desktop.desktop
/usr/share/icons/hicolor/*/apps/claude-desktop.png

%changelog
* $(date "+%a %b %d %Y") Auto Builder <builder@localhost> - $INSTALLER_VERSION-1
- Automated build from official Claude Desktop installer
EOF

    # Ensure resources directory exists
    mkdir -p "$BUILD_DIR/electron/resources"

    # Build RPM
    rpmbuild --define "_topdir $rpm_root" \
             --define "_builddir $BUILD_DIR" \
             -bb "$rpm_root/SPECS/claude-desktop.spec" &>/dev/null || {
        log_error "Failed to build RPM package"
        exit 1
    }

    local rpm_file=$(find "$rpm_root/RPMS" -name "*.rpm" | head -1)
    if [[ -z "$rpm_file" ]]; then
        log_error "RPM package not found"
        exit 1
    fi

    log_success "RPM package built"
    echo "$rpm_file"
}

# Install RPM
install_rpm() {
    local rpm_file="$1"

    log_info "Installing Claude Desktop..."

    # Remove old version if exists
    if rpm -q claude-desktop &>/dev/null; then
        log_info "Removing old version..."
        dnf remove -y claude-desktop &>/dev/null
    fi

    # Install new version
    dnf install -y "$rpm_file" || {
        log_error "Failed to install RPM package"
        exit 1
    }

    log_success "Claude Desktop installed successfully!"
}

# Main installation flow
main() {
    print_banner
    check_root
    check_system

    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Run installation steps
    install_dependencies
    setup_node
    download_electron
    download_claude
    process_asar
    extract_icons

    # Build and install
    local rpm_file=$(create_rpm)
    install_rpm "$rpm_file"

    # Success message
    echo
    log_success "Installation complete! You can now run 'claude-desktop' to start the application."
    echo
    log_info "To update in the future, simply run this installer again."
}

# Run main function
main "$@"
