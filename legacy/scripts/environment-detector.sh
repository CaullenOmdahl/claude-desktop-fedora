#!/bin/bash
# Environment detection for optimal backend selection
# Claude Desktop Fedora Performance Optimization - Phase 1

detect_session_type() {
    echo "${XDG_SESSION_TYPE:-unknown}"
}

detect_desktop_environment() {
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]'
    elif [ -n "$DESKTOP_SESSION" ]; then
        echo "$DESKTOP_SESSION" | tr '[:upper:]' '[:lower:]'
    elif [ -n "$GNOME_DESKTOP_SESSION_ID" ]; then
        echo "gnome"
    elif [ -n "$KDE_FULL_SESSION" ]; then
        echo "kde"
    else
        echo "unknown"
    fi
}

get_gnome_version() {
    if command -v gnome-shell >/dev/null 2>&1; then
        gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "0"
    else
        echo "0"
    fi
}

has_wayland_support() {
    [ "$XDG_SESSION_TYPE" = "wayland" ] && [ -n "$WAYLAND_DISPLAY" ]
}

get_optimal_backend() {
    local session=$(detect_session_type)
    local desktop=$(detect_desktop_environment)
    local gnome_version=$(get_gnome_version)

    # Use Wayland natively on supported environments
    if has_wayland_support; then
        case "$desktop" in
            *gnome*)
                if [ "$gnome_version" -ge 40 ]; then
                    echo "wayland"
                else
                    echo "x11"
                fi
                ;;
            *kde*|*plasma*)
                echo "wayland"  # KDE Plasma has excellent Wayland support
                ;;
            *sway*)
                echo "wayland"  # Sway is Wayland-native
                ;;
            *hyprland*)
                echo "wayland"  # Hyprland is Wayland-native
                ;;
            *)
                echo "x11"  # Conservative fallback for unknown DEs
                ;;
        esac
    else
        echo "x11"  # X11 session or no Wayland support
    fi
}

export_optimal_backend() {
    local backend=$(get_optimal_backend)

    # Allow manual override
    if [ -n "$CLAUDE_FORCE_BACKEND" ]; then
        backend="$CLAUDE_FORCE_BACKEND"
        echo "Backend override detected: $backend" >&2
    fi

    export GDK_BACKEND="$backend"

    echo "Environment Detection Results:" >&2
    echo "  Session Type: $(detect_session_type)" >&2
    echo "  Desktop Environment: $(detect_desktop_environment)" >&2
    echo "  GNOME Version: $(get_gnome_version)" >&2
    echo "  Wayland Support: $(has_wayland_support && echo 'Yes' || echo 'No')" >&2
    echo "  Selected Backend: $backend" >&2
}

# Debug mode for troubleshooting
debug_environment() {
    echo "=== Environment Debug Information ==="
    echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-unset}"
    echo "XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-unset}"
    echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-unset}"
    echo "DESKTOP_SESSION: ${DESKTOP_SESSION:-unset}"
    echo "GNOME_DESKTOP_SESSION_ID: ${GNOME_DESKTOP_SESSION_ID:-unset}"
    echo "KDE_FULL_SESSION: ${KDE_FULL_SESSION:-unset}"
    echo "Detected Session: $(detect_session_type)"
    echo "Detected Desktop: $(detect_desktop_environment)"
    echo "GNOME Version: $(get_gnome_version)"
    echo "Optimal Backend: $(get_optimal_backend)"
    echo "================================="
}

# Export functions for sourcing
export -f detect_session_type
export -f detect_desktop_environment
export -f get_gnome_version
export -f has_wayland_support
export -f get_optimal_backend
export -f export_optimal_backend
export -f debug_environment
