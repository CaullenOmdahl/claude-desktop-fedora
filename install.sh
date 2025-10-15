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
readonly INSTALLER_VERSION="3.2.6"
readonly ELECTRON_VERSION="37.0.0"
readonly CLAUDE_VERSION="0.12.129"
readonly BUILD_DIR="/tmp/claude-desktop-build-$$"
readonly CLAUDE_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

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

    # Check if there's an app.asar.unpacked directory (contains native modules)
    if [[ -d "extracted/lib/net45/resources/app.asar.unpacked" ]]; then
        cp -r extracted/lib/net45/resources/app.asar.unpacked .
    fi

    # Extract and modify app.asar (ignore errors about unpacked files)
    npx asar extract app.asar app-unpacked || true

    # Merge unpacked files if they exist
    if [[ -d "app.asar.unpacked" ]]; then
        cp -r app.asar.unpacked/* app-unpacked/ 2>/dev/null || true
    fi

    # Copy i18n resources (they're separate from app.asar)
    # The i18n JSON files are in lib/net45/resources/ but need to be in resources/i18n/
    if [[ -f "extracted/lib/net45/resources/en-US.json" ]]; then
        log_info "Copying i18n resources to app"
        mkdir -p app-unpacked/resources/i18n
        cp extracted/lib/net45/resources/*.json app-unpacked/resources/i18n/ 2>/dev/null || true
        log_success "i18n resources copied"
    else
        log_error "Warning: i18n resources not found in extracted installer"
    fi

    # Apply window dragging fix to main window HTML
    # Claude Desktop uses Vite structure: .vite/renderer/main_window/index.html
    local main_html="app-unpacked/.vite/renderer/main_window/index.html"

    if [[ -f "$main_html" ]]; then
        log_info "Applying window dragging fix to $main_html"

        # Add CSS for window dragging
        # Claude Desktop loads content dynamically and uses .nc-drag/.nc-no-drag classes
        # We need to make the top area draggable by default and let the app control specifics
        sed -i '/<head>/a\    <style id="linux-window-drag">\n      /* Make top ~50px of window draggable as a fallback */\n      body::before {\n        content: "";\n        position: fixed;\n        top: 0;\n        left: 0;\n        right: 0;\n        height: 50px;\n        -webkit-app-region: drag;\n        pointer-events: none;\n        z-index: 999999;\n      }\n      \n      /* Respect apps native drag/no-drag classes */\n      .nc-drag {\n        -webkit-app-region: drag !important;\n      }\n      \n      .nc-no-drag {\n        -webkit-app-region: no-drag !important;\n        pointer-events: auto !important;\n      }\n      \n      /* Make all interactive elements no-drag with higher z-index */\n      button, input, textarea, select, a, [role="button"],\n      [contenteditable="true"], [tabindex]:not([tabindex="-1"]) {\n        -webkit-app-region: no-drag !important;\n        position: relative;\n        z-index: 9999999;\n        pointer-events: auto !important;\n      }\n    </style>' "$main_html"

        log_success "Window dragging CSS applied"
    else
        log_warn "Main window HTML not found at $main_html"
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

    # Extract colored icon from the Setup.exe (contains full-color app icon)
    # The Tray icons are intentionally monochrome for system trays
    local setup_exe="Claude-Setup.exe"
    if [[ -f "$setup_exe" ]]; then
        log_info "Extracting colored icon from Setup.exe"

        # Extract the setup icon resource (type 3, largest colored icon)
        wrestool -x -t3 -n6 "$setup_exe" -o setupIcon.ico 2>/dev/null || true

        if [[ -f "setupIcon.ico" ]]; then
            local ico_file="setupIcon.ico"
            log_info "Using colored Setup icon"
        fi
    fi

    # Fallback to Tray icon if setup icon extraction failed
    if [[ -z "$ico_file" || ! -f "$ico_file" ]]; then
        log_warn "Setup icon not found, falling back to Tray icon"
        if [[ -f "extracted/lib/net45/resources/Tray-Win32.ico" ]]; then
            ico_file="extracted/lib/net45/resources/Tray-Win32.ico"
        elif [[ -f "extracted/lib/net45/claude-desktop.ico" ]]; then
            ico_file="extracted/lib/net45/claude-desktop.ico"
        else
            ico_file=$(find extracted -name "*.ico" | grep -v Dark | head -1)
        fi
    fi

    if [[ -n "$ico_file" && -f "$ico_file" ]]; then
        log_info "Extracting icons from $(basename "$ico_file")"

        # Extract all icons using icotool
        # This preserves colors perfectly - no need for ImageMagick conversion!
        icotool -x "$ico_file" -o . 2>/dev/null || true

        # Map extracted icons to standard sizes
        # icotool creates files like: basename_N_WIDTHxHEIGHTxDEPTH.png
        local base_name=$(basename "$ico_file" .ico)

        for size in 16 32 48 64 128 256 512; do
            # Try to find exact size with 32-bit depth (best quality)
            local found=0
            for extracted in ${base_name}_*_${size}x${size}x32.png; do
                if [[ -f "$extracted" ]]; then
                    cp "$extracted" "claude-desktop-${size}.png"
                    found=1
                    break
                fi
            done

            # If no exact match, try any depth at this size
            if [[ $found -eq 0 ]]; then
                for extracted in ${base_name}_*_${size}x${size}*.png; do
                    if [[ -f "$extracted" ]]; then
                        cp "$extracted" "claude-desktop-${size}.png"
                        found=1
                        break
                    fi
                done
            fi

            # If still no match, scale from nearest available size using ImageMagick
            if [[ $found -eq 0 ]]; then
                # Find closest 32-bit icon
                local closest=""
                local closest_size=999999
                for extracted in ${base_name}_*_*x*x32.png; do
                    if [[ -f "$extracted" ]]; then
                        local dims=$(echo "$extracted" | grep -oP '\d+x\d+' | head -1)
                        local icon_size=$(echo "$dims" | cut -d'x' -f1)
                        local diff=$((size > icon_size ? size - icon_size : icon_size - size))
                        if [[ $diff -lt $closest_size ]]; then
                            closest="$extracted"
                            closest_size=$diff
                        fi
                    fi
                done

                if [[ -n "$closest" ]]; then
                    # Resize without modifying colors - icons already have proper colors
                    convert "$closest" -resize ${size}x${size} "claude-desktop-${size}.png" 2>/dev/null || true
                fi
            fi
        done

        # Clean up temporary extracted files
        rm -f ${base_name}_*.png 2>/dev/null || true

        log_success "Icons extracted (original colors preserved)"
    else
        log_warn "No icon file found"
    fi
}

# Create RPM package
create_rpm() {

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
mkdir -p %{buildroot}/usr/lib64/claude-desktop/resources
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/{16x16,32x32,48x48,64x64,128x128,256x256,512x512}/apps

# Copy Electron
cp -r $BUILD_DIR/electron/* %{buildroot}/usr/lib64/claude-desktop/electron/

# Copy app files
cp $BUILD_DIR/app.asar %{buildroot}/usr/lib64/claude-desktop/resources/app.asar

# Copy unpacked files if they exist
if [[ -d "$BUILD_DIR/app-unpacked" ]]; then
    cp -r $BUILD_DIR/app-unpacked %{buildroot}/usr/lib64/claude-desktop/resources/
fi

# Copy icons (handle multiple icon versions)
for size in 16 32 48 64 128 256 512; do
    # Look for any icon of this size
    icon_file=\$(ls $BUILD_DIR/claude-desktop-\${size}*.png 2>/dev/null | head -1)
    if [[ -n "\$icon_file" ]]; then
        cp "\$icon_file" %{buildroot}/usr/share/icons/hicolor/\${size}x\${size}/apps/claude-desktop.png
    fi
done

# Create default icon if none exist
if ! ls %{buildroot}/usr/share/icons/hicolor/*/apps/*.png 1> /dev/null 2>&1; then
    echo "Creating default icon..."
    mkdir -p %{buildroot}/usr/share/icons/hicolor/48x48/apps/
    touch %{buildroot}/usr/share/icons/hicolor/48x48/apps/claude-desktop.png
fi

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
%defattr(-,root,root,-)
/usr/lib64/claude-desktop/
/usr/bin/claude-desktop
/usr/share/applications/claude-desktop.desktop
# Include all icon directories that exist
/usr/share/icons/hicolor/*/apps/*.png

%changelog
* $(date "+%a %b %d %Y") Auto Builder <builder@localhost> - $INSTALLER_VERSION-1
- Automated build from official Claude Desktop installer
EOF

    # Ensure resources directory exists
    mkdir -p "$BUILD_DIR/electron/resources"

    # Build RPM (suppress output except errors)
    if ! rpmbuild --define "_topdir $rpm_root" \
                  --define "_builddir $BUILD_DIR" \
                  -bb "$rpm_root/SPECS/claude-desktop.spec" >/dev/null 2>&1; then
        log_error "Failed to build RPM package"
        return 1
    fi

    local rpm_file=$(find "$rpm_root/RPMS" -name "*.rpm" | head -1)
    if [[ -z "$rpm_file" ]]; then
        log_error "RPM package not found"
        return 1
    fi

    log_success "RPM package built: $(basename "$rpm_file")" >&2
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
    if ! dnf install -y "$rpm_file" 2>&1; then
        log_error "Failed to install RPM package"
        exit 1
    fi

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

    # Build RPM
    log_info "Building RPM package..."
    local rpm_file=$(create_rpm)
    if [[ -z "$rpm_file" ]]; then
        log_error "Failed to create RPM package"
        exit 1
    fi

    # Install RPM
    install_rpm "$rpm_file"

    # Success message
    echo
    log_success "Installation complete! You can now run 'claude-desktop' to start the application."
    echo
    log_info "To update in the future, simply run this installer again."
}

# Run main function
main "$@"
