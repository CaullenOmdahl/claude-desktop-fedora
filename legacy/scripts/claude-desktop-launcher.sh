#!/bin/bash
# Claude Desktop Optimized Launcher
# Performance Optimization Implementation - Phases 1 & 2

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
