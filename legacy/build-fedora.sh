#!/bin/bash
set -e

# Cleanup function to remove build directories on exit
cleanup_build() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "🧹 Cleaning up build directories after failure..."
        rm -rf "${WORK_DIR:-/tmp/build}" /tmp/Claude-* /tmp/electron.zip 2>/dev/null || true
        echo "Build cleanup completed"
    fi
}

# Set up cleanup trap for failures
trap cleanup_build EXIT

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Inclusive check for Fedora-based system
is_fedora_based() {
    if [ -f "/etc/fedora-release" ]; then
        return 0
    fi

    if [ -f "/etc/os-release" ]; then
        grep -qi "fedora" /etc/os-release && return 0
    fi

    # Not a Fedora-based system
    return 1
}

if ! is_fedora_based; then
    echo "❌ This script requires a Fedora-based Linux distribution"
    exit 1
fi

# Check for root/sudo
IS_SUDO=false
if [ "$EUID" -eq 0 ]; then
    IS_SUDO=true
    # Check if running via sudo (and not directly as root)
    if [ -n "$SUDO_USER" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo ~$ORIGINAL_USER)
    else
        # Running directly as root, no original user context
        ORIGINAL_USER="root"
        ORIGINAL_HOME="/root"
    fi
else
    echo "Please run with sudo to install dependencies"
    exit 1
fi

# Setup Node.js/npm path - check if already available before using NVM
if ! command -v npm &> /dev/null || ! command -v npx &> /dev/null; then
    # Only setup NVM if npm/npx not already available
    if [ "$IS_SUDO" = true ] && [ "$ORIGINAL_USER" != "root" ] && [ -d "$ORIGINAL_HOME/.nvm" ]; then
        echo "npm/npx not found in PATH, checking NVM installation for user $ORIGINAL_USER..."
        # Source NVM script to set up NVM environment variables temporarily
        export NVM_DIR="$ORIGINAL_HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

        # Find the path to the currently active or default Node version's bin directory
        NODE_BIN_PATH=$(find "$NVM_DIR/versions/node" -maxdepth 2 -type d -name 'bin' | sort -V | tail -n 1)

        if [ -n "$NODE_BIN_PATH" ] && [ -d "$NODE_BIN_PATH" ]; then
            echo "Adding $NODE_BIN_PATH to PATH"
            export PATH="$NODE_BIN_PATH:$PATH"
        else
            echo "Warning: Could not determine NVM Node bin path. npm/npx might not be found."
        fi
    fi
else
    echo "✓ npm/npx already available in PATH"
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
echo "Fedora version: $(cat /etc/fedora-release)"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Check and install dependencies
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Check system package dependencies
for cmd in sqlite3 7z wget wrestool icotool convert npx rpm rpmbuild notify-send; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "sqlite3")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL sqlite3"
                ;;
            "7z")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip-plugins"
                ;;
            "wget")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget"
                ;;
            "wrestool"|"icotool")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils"
                ;;
            "convert")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL ImageMagick"
                ;;
            "npx")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL nodejs npm"
                ;;
            "rpm")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL rpm"
                ;;
            "rpmbuild")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL rpmbuild"
                ;;
            "notify-send")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL libnotify"
                ;;
            "curl")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL curl"
        esac
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    echo "Installing system dependencies: $DEPS_TO_INSTALL"
    dnf install -y $DEPS_TO_INSTALL
    echo "System dependencies installed successfully"
fi

# Download and prepare Electron for bundling
ELECTRON_VERSION="v37.0.0"
ELECTRON_URL="https://github.com/electron/electron/releases/download/${ELECTRON_VERSION}/electron-${ELECTRON_VERSION}-linux-x64.zip"
ELECTRON_DIR="$WORK_DIR/electron"

echo "📥 Downloading Electron ${ELECTRON_VERSION}..."
ELECTRON_ZIP="$WORK_DIR/electron.zip"
if ! curl -L -o "$ELECTRON_ZIP" "$ELECTRON_URL"; then
    echo "❌ Failed to download Electron"
    exit 1
fi

echo "📦 Extracting Electron..."
# Clean any existing electron directory to prevent conflicts
rm -rf "$ELECTRON_DIR"
mkdir -p "$ELECTRON_DIR"
if ! unzip -o -q "$ELECTRON_ZIP" -d "$ELECTRON_DIR"; then
    echo "❌ Failed to extract Electron"
    exit 1
fi
chmod +x "$ELECTRON_DIR/electron"
echo "✓ Electron prepared for bundling"

PACKAGE_NAME="claude-desktop"
ARCHITECTURE=$(uname -m)
DISTRIBUTION=$(rpm --eval %{?dist})
MAINTAINER="Claude Desktop Linux Maintainers"
DESCRIPTION="Claude Desktop for Linux"

# Create working directories
WORK_DIR="$(pwd)/build"
FEDORA_ROOT="$WORK_DIR/fedora-package"
INSTALL_DIR="$FEDORA_ROOT/usr"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$FEDORA_ROOT/FEDORA"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/electron"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"

# Install asar if needed
if ! command -v asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
if ! curl -o "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Find the nupkg file
NUPKG_FILE=$(find . -name "AnthropicClaude-*-full.nupkg" | head -1)
if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Could not find AnthropicClaude nupkg file"
    exit 1
fi

# Use independent versioning
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '\n\r')
    echo "📋 Using package version: $VERSION"
elif [ -f "VERSION" ]; then
    VERSION=$(cat VERSION | tr -d '\n\r')
    echo "📋 Using package version: $VERSION"
elif [ -f "/tmp/VERSION" ]; then
    VERSION=$(cat /tmp/VERSION | tr -d '\n\r')
    echo "📋 Using package version: $VERSION (from /tmp/VERSION)"
else
    echo "❌ VERSION file not found in $SCRIPT_DIR, current directory, or /tmp/"
    exit 1
fi

# Extract Claude version for reference
CLAUDE_VERSION=$(echo "$NUPKG_FILE" | grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full\.nupkg)')
echo "📋 Claude Desktop version: $CLAUDE_VERSION (bundled)"

if ! 7z x -y "$NUPKG_FILE"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    exit 1
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

cd electron-app
npx asar extract app.asar app.asar.contents || { echo "asar extract failed"; exit 1; }

echo "Configuring window frame for Linux compatibility..."

# Multiple approaches to fix window dragging issues
echo "Applying window management fixes..."

# Method 1: Remove titleBarOverlay and problematic settings
sed -i 's/titleBarStyle:"[^"]*"/titleBarStyle:"default"/g' app.asar.contents/.vite/build/index.js
sed -i 's/titleBarOverlay:[^,}]*/titleBarOverlay:false/g' app.asar.contents/.vite/build/index.js
sed -i 's/frame:false/frame:false/g' app.asar.contents/.vite/build/index.js

# Method 2: Try broader pattern matching
find app.asar.contents/.vite -name "*.js" -exec sed -i 's/titleBarOverlay:[^,}]*[,}]/titleBarOverlay:false,/g' {} \;

# Method 3: Add explicit draggable region CSS if HTML files exist
if [ -f app.asar.contents/.vite/renderer/main_window/index.html ]; then
    echo "Adding draggable region CSS..."
    sed -i 's/<head>/<head><style>.title-bar{-webkit-app-region:drag;} .title-bar *{-webkit-app-region:no-drag;}<\/style>/g' app.asar.contents/.vite/renderer/main_window/index.html
fi

echo "Window management configuration applied"

# Replace native module with enhanced Fedora 42 implementation
echo "Creating enhanced native module for Fedora 42..."
if [ -f "$SCRIPT_DIR/claude-native-enhanced.js" ]; then
    cp "$SCRIPT_DIR/claude-native-enhanced.js" app.asar.contents/node_modules/claude-native/index.js
    echo "✓ Enhanced native bindings installed (claude-native-enhanced.js)"
elif [ -f "$SCRIPT_DIR/claude-native-improved.js" ]; then
    cp "$SCRIPT_DIR/claude-native-improved.js" app.asar.contents/node_modules/claude-native/index.js
    echo "✓ Enhanced native bindings installed (claude-native-improved.js)"
elif [ -f "/tmp/claude-native-enhanced.js" ]; then
    cp "/tmp/claude-native-enhanced.js" app.asar.contents/node_modules/claude-native/index.js
    echo "✓ Enhanced native bindings installed (from /tmp)"
else
    echo "⚠ Enhanced bindings not found, using fallback stub"
    # Fallback to simple stub if enhanced version not available
    cat > app.asar.contents/node_modules/claude-native/index.js << 'FALLBACK_EOF'
const KeyboardKey = {
  Backspace: 8, Tab: 9, Enter: 13, Shift: 16, Control: 17, Alt: 18,
  CapsLock: 20, Escape: 27, Space: 32, PageUp: 33, PageDown: 34,
  End: 35, Home: 36, LeftArrow: 37, UpArrow: 38, RightArrow: 39,
  DownArrow: 40, Delete: 46, Meta: 91
};
module.exports = {
  getWindowsVersion: () => "10.0.0", setWindowEffect: () => {}, removeWindowEffect: () => {},
  getIsMaximized: () => false, flashFrame: () => {}, clearFlashFrame: () => {},
  showNotification: () => {}, setProgressBar: () => {}, clearProgressBar: () => {},
  setOverlayIcon: () => {}, clearOverlayIcon: () => {}, KeyboardKey
};
FALLBACK_EOF
fi

# Copy Tray icons
mkdir -p app.asar.contents/resources
cp ../lib/net45/resources/Tray* app.asar.contents/resources/

# Repackage app.asar
mkdir -p app.asar.contents/resources/i18n/
cp ../lib/net45/resources/*.json app.asar.contents/resources/i18n/

echo "Downloading Main Window Fix Assets"
cd app.asar.contents
wget -O- https://github.com/emsi/claude-desktop/raw/refs/heads/main/assets/main_window.tgz | tar -zxvf -
cd ..

npx asar pack app.asar.contents app.asar || { echo "asar pack failed"; exit 1; }

# Install enhanced native module in final location
echo "Installing enhanced native bindings..."
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
if [ -f "$SCRIPT_DIR/claude-native-improved.js" ]; then
    cp "$SCRIPT_DIR/claude-native-improved.js" "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js"
    echo "✓ Enhanced native bindings installed in final location"
else
    echo "⚠ Enhanced bindings not found, creating fallback stub"
    cat > "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js" << 'FALLBACK_EOF'
const KeyboardKey = {
  Backspace: 8, Tab: 9, Enter: 13, Shift: 16, Control: 17, Alt: 18,
  CapsLock: 20, Escape: 27, Space: 32, PageUp: 33, PageDown: 34,
  End: 35, Home: 36, LeftArrow: 37, UpArrow: 38, RightArrow: 39,
  DownArrow: 40, Delete: 46, Meta: 91
};
module.exports = {
  getWindowsVersion: () => "10.0.0", setWindowEffect: () => {}, removeWindowEffect: () => {},
  getIsMaximized: () => false, flashFrame: () => {}, clearFlashFrame: () => {},
  showNotification: () => {}, setProgressBar: () => {}, clearProgressBar: () => {},
  setOverlayIcon: () => {}, clearOverlayIcon: () => {}, KeyboardKey
};
FALLBACK_EOF
fi

# Copy app files
cp app.asar "$INSTALL_DIR/lib/$PACKAGE_NAME/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/$PACKAGE_NAME/"

# Copy performance optimization scripts
echo "📦 Installing performance optimization scripts..."
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts"
if [ -f "/tmp/scripts/environment-detector.sh" ]; then
    cp "/tmp/scripts/environment-detector.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Environment detector installed"
elif [ -f "$SCRIPT_DIR/scripts/environment-detector.sh" ]; then
    cp "$SCRIPT_DIR/scripts/environment-detector.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Environment detector installed (local copy)"
else
    echo "⚠ Environment detector not found, using fallback"
fi
if [ -f "/tmp/scripts/electron-args-builder.sh" ]; then
    cp "/tmp/scripts/electron-args-builder.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Electron args builder installed"
elif [ -f "$SCRIPT_DIR/scripts/electron-args-builder.sh" ]; then
    cp "$SCRIPT_DIR/scripts/electron-args-builder.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Electron args builder installed (local copy)"
else
    echo "⚠ Electron args builder not found, using fallback"
fi
chmod +x "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts"/*.sh 2>/dev/null

# Bundle Electron in the RPM
echo "📦 Bundling Electron in RPM package..."
cp -r "$ELECTRON_DIR"/* "$INSTALL_DIR/lib/$PACKAGE_NAME/electron/"
echo "✓ Electron bundled successfully"

# Create desktop entry
cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF

# Create optimized launcher script with bundled Electron
cat > "$INSTALL_DIR/bin/claude-desktop" << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/claude-desktop-launcher.log"

# Performance optimization scripts path
SCRIPTS_DIR="/usr/lib64/claude-desktop/scripts"

# Source optimization scripts if available
if [ -f "$SCRIPTS_DIR/environment-detector.sh" ]; then
    source "$SCRIPTS_DIR/environment-detector.sh"
    export_optimal_backend
else
    # Fallback to X11 if scripts not available
    export GDK_BACKEND=x11
    echo "Using fallback X11 backend (optimization scripts not found)" >&2
fi

if [ -f "$SCRIPTS_DIR/electron-args-builder.sh" ]; then
    source "$SCRIPTS_DIR/electron-args-builder.sh"
    export_electron_args
else
    # Fallback electron arguments
    export ELECTRON_ARGS="--ozone-platform-hint=auto --enable-logging=file --log-level=INFO --disable-gpu-sandbox --no-sandbox"
    echo "Using fallback Electron arguments (optimization scripts not found)" >&2
fi

# Additional optimizations based on backend
if [ "$GDK_BACKEND" = "wayland" ]; then
    export GTK_USE_PORTAL=1
    export QT_QPA_PLATFORM=wayland
    export MOZ_ENABLE_WAYLAND=1
else
    export GTK_USE_PORTAL=0
    export QT_QPA_PLATFORM=xcb
fi

# Common environment variables
export ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Debug mode support
if [ "$CLAUDE_DEBUG" = "1" ]; then
    echo "=== Claude Desktop Debug Mode ===" >&2
    if command -v debug_environment >/dev/null 2>&1; then
        debug_environment
    fi
    if command -v debug_electron_config >/dev/null 2>&1; then
        debug_electron_config
    fi
    echo "Log file: $LOG_FILE" >&2
    echo "============================" >&2
fi

# Launch Claude Desktop with optimized configuration
exec /usr/lib64/claude-desktop/electron/electron \
    /usr/lib64/claude-desktop/app.asar \
    $ELECTRON_ARGS \
    --log-file="$LOG_FILE" \
    "$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

# Create RPM spec file
cat > "$WORK_DIR/claude-desktop.spec" << EOF
Name:           claude-desktop
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Claude Desktop for Linux
License:        Proprietary
URL:            https://www.anthropic.com
BuildArch:      ${ARCHITECTURE}
Requires:       p7zip

%description
Claude Desktop for Linux - unofficial build for Fedora-based distributions.
This package bundles Claude Desktop ${CLAUDE_VERSION} with all dependencies.
Provides native Linux integration including system tray and MCP support.

%install
mkdir -p %{buildroot}/usr/lib64/%{name}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons

# Copy files from the INSTALL_DIR
cp -r ${INSTALL_DIR}/lib/%{name}/* %{buildroot}/usr/lib64/%{name}/
cp -r ${INSTALL_DIR}/bin/* %{buildroot}/usr/bin/
cp -r ${INSTALL_DIR}/share/applications/* %{buildroot}/usr/share/applications/
cp -r ${INSTALL_DIR}/share/icons/* %{buildroot}/usr/share/icons/

%files
%{_bindir}/claude-desktop
%{_libdir}/%{name}
%{_datadir}/applications/claude-desktop.desktop
%{_datadir}/icons/hicolor/*/apps/claude-desktop.png

%post
# Update icon caches
gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor || :
# Force icon theme cache rebuild
touch -h %{_datadir}/icons/hicolor >/dev/null 2>&1 || :
update-desktop-database %{_datadir}/applications || :

# Set correct permissions for bundled chrome-sandbox
echo "Setting chrome-sandbox permissions..."
SANDBOX_PATH="/usr/lib64/claude-desktop/electron/chrome-sandbox"
if [ -f "\$SANDBOX_PATH" ]; then
    echo "Found bundled chrome-sandbox at: \$SANDBOX_PATH"
    chown root:root "\$SANDBOX_PATH" || echo "Warning: Failed to chown chrome-sandbox"
    chmod 4755 "\$SANDBOX_PATH" || echo "Warning: Failed to chmod chrome-sandbox"
    echo "Permissions set for bundled chrome-sandbox"
else
    echo "Warning: Bundled chrome-sandbox binary not found. Sandbox may not function correctly."
fi

%changelog
* $(date '+%a %b %d %Y') ${MAINTAINER} ${VERSION}-1
- Initial package
EOF

# Build RPM package
echo "📦 Building RPM package..."
mkdir -p "${WORK_DIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

RPM_FILE="$(pwd)/${ARCHITECTURE}/claude-desktop-${VERSION}-1${DISTRIBUTION}.$(uname -m).rpm"
if rpmbuild -bb \
    --define "_topdir ${WORK_DIR}" \
    --define "_rpmdir $(pwd)" \
    "${WORK_DIR}/claude-desktop.spec"; then
    echo "✓ RPM package built successfully at: $RPM_FILE"
    echo "🎉 Done! You can now install the RPM with: dnf install $RPM_FILE"
else
    echo "❌ Failed to build RPM package"
    exit 1
fi
