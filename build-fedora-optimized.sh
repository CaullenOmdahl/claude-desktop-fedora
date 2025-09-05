#!/bin/bash
# This is a patch to demonstrate the key changes needed for build-fedora.sh
# The changes integrate performance optimization scripts

# Key changes needed:

# 1. After the "Copy app files" section, add script installation:
echo "After line with 'cp -r app.asar.unpacked' add:"
cat << 'PATCH1'

# Copy performance optimization scripts
echo "📦 Installing performance optimization scripts..."
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts"
if [ -f "$SCRIPT_DIR/scripts/environment-detector.sh" ]; then
    cp "$SCRIPT_DIR/scripts/environment-detector.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Environment detector installed"
fi
if [ -f "$SCRIPT_DIR/scripts/electron-args-builder.sh" ]; then
    cp "$SCRIPT_DIR/scripts/electron-args-builder.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
    echo "✓ Electron args builder installed"
fi
chmod +x "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts"/*.sh 2>/dev/null
PATCH1

echo ""
echo "2. Replace the launcher script creation section with:"
cat << 'PATCH2'
cat > "$INSTALL_DIR/bin/claude-desktop" << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/claude-desktop-launcher.log"
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
exec /usr/lib64/claude-desktop/electron/electron \
    /usr/lib64/claude-desktop/app.asar \
    $ELECTRON_ARGS \
    --log-file="$LOG_FILE" \
    "$@"
EOF
PATCH2

echo ""
echo "Manual steps to apply these changes:"
echo "1. Edit build-fedora.sh manually"
echo "2. Find the 'Copy app files' section and add PATCH1 after it"
echo "3. Replace the launcher creation section with PATCH2"
echo "4. Save the file"
