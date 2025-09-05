#!/bin/bash
# GNOME-specific integration enhancements
# Claude Desktop Fedora Performance Optimization - Phase 5

get_gnome_version() {
    if command -v gnome-shell >/dev/null 2>&1; then
        gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "0"
    else
        echo "0"
    fi
}

check_gnome_extensions() {
    if ! command -v gnome-extensions >/dev/null 2>&1; then
        echo "GNOME Extensions not available"
        return 1
    fi

    local gnome_version=$(get_gnome_version)
    echo "Detected GNOME version: $gnome_version"

    # Extensions that improve Claude Desktop integration
    local required_extensions=(
        "appindicatorsupport@rgcjonas.gmail.com"      # System tray support
        "user-theme@gnome-shell-extensions.gcampax.github.com"  # Theme customization
    )

    local recommended_extensions=(
        "blur-my-shell@aunetx"                        # Visual enhancements
        "dash-to-panel@jderose9.github.com"           # Better taskbar
        "just-perfection-desktop@just-perfection"     # Desktop tweaks
    )

    local missing_required=()
    local missing_recommended=()

    echo "Checking required extensions for Claude Desktop integration..."
    for ext in "${required_extensions[@]}"; do
        if ! gnome-extensions list 2>/dev/null | grep -q "$ext"; then
            missing_required+=("$ext")
        else
            echo "  ✓ $ext (installed)"
        fi
    done

    echo ""
    echo "Checking recommended extensions for better experience..."
    for ext in "${recommended_extensions[@]}"; do
        if ! gnome-extensions list 2>/dev/null | grep -q "$ext"; then
            missing_recommended+=("$ext")
        else
            echo "  ✓ $ext (installed)"
        fi
    done

    # Report missing extensions
    if [ ${#missing_required[@]} -gt 0 ]; then
        echo ""
        echo "🔧 Required GNOME Extensions for Claude Desktop system tray:"
        for ext in "${missing_required[@]}"; do
            case "$ext" in
                "appindicatorsupport@rgcjonas.gmail.com")
                    echo "  • AppIndicator Support - Enables system tray for Claude Desktop"
                    echo "    Install: https://extensions.gnome.org/extension/615/appindicator-support/"
                    ;;
                *)
                    echo "  • $ext"
                    ;;
            esac
        done
        echo ""
        echo "Without these extensions, Claude Desktop system tray may not work properly."
    else
        echo ""
        echo "✓ All required GNOME extensions are installed for Claude Desktop"
    fi

    if [ ${#missing_recommended[@]} -gt 0 ]; then
        echo ""
        echo "💡 Recommended GNOME Extensions for better experience:"
        for ext in "${missing_recommended[@]}"; do
            case "$ext" in
                "blur-my-shell@aunetx")
                    echo "  • Blur my Shell - Visual enhancements for Claude Desktop windows"
                    ;;
                "dash-to-panel@jderose9.github.com")
                    echo "  • Dash to Panel - Better taskbar integration"
                    ;;
                *)
                    echo "  • $ext"
                    ;;
            esac
        done
        echo ""
        echo "Install via: https://extensions.gnome.org/"
    fi
}

setup_gnome_integration() {
    local gnome_version=$(get_gnome_version)

    if [ "$gnome_version" -lt 40 ]; then
        echo "⚠ GNOME version $gnome_version is quite old. Consider upgrading for better Claude Desktop support."
        return 1
    fi

    echo "Setting up GNOME integration for Claude Desktop..."

    # Create GNOME-specific desktop file with better integration
    local desktop_file="$HOME/.local/share/applications/claude-desktop-gnome.desktop"
    mkdir -p "$(dirname "$desktop_file")"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Claude (Optimized)
Comment=Claude Desktop with GNOME integration
Exec=env CLAUDE_GNOME_INTEGRATION=1 claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Development;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
StartupNotify=true
Keywords=AI;Assistant;Claude;Anthropic;
EOF

    # Set up GNOME-specific shortcuts
    setup_gnome_shortcuts

    echo "✓ GNOME integration configured"
    echo "  • Desktop file created with GNOME optimizations"
    echo "  • Custom shortcuts configured"
    echo "  • Use 'Claude (Optimized)' from applications menu for best experience"
}

setup_gnome_shortcuts() {
    # Try to set up Ctrl+Alt+Space shortcut for GNOME
    if command -v gsettings >/dev/null 2>&1; then
        echo "Configuring GNOME keyboard shortcuts..."

        # Check if we can set custom shortcuts
        local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
        local claude_shortcut_path="$shortcut_path/claude-desktop/"

        # Set the custom keybinding
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$claude_shortcut_path name 'Claude Desktop'
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$claude_shortcut_path command 'claude-desktop'
        gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$claude_shortcut_path binding '<Ctrl><Alt>space'

        # Add to the list of custom keybindings
        local current_shortcuts=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        if [[ "$current_shortcuts" != *"$claude_shortcut_path"* ]]; then
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
                "$(echo "$current_shortcuts" | sed "s/]/, '$claude_shortcut_path']/")"
        fi

        echo "  ✓ Ctrl+Alt+Space shortcut configured for Claude Desktop"
    else
        echo "  ⚠ gsettings not available, unable to configure shortcuts"
    fi
}

check_wayland_performance() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        echo "🚀 GNOME Wayland Performance Check:"

        # Check for performance-related settings
        if command -v gsettings >/dev/null 2>&1; then
            local animations=$(gsettings get org.gnome.desktop.interface enable-animations)
            local scaling=$(gsettings get org.gnome.desktop.interface scaling-factor)

            echo "  • Animations: $animations"
            echo "  • Scaling factor: $scaling"

            # Suggest optimizations
            if [ "$animations" = "true" ]; then
                echo "  💡 Consider disabling animations for better Claude Desktop performance:"
                echo "     gsettings set org.gnome.desktop.interface enable-animations false"
            fi

            # Check for hardware acceleration
            if command -v vainfo >/dev/null 2>&1 && [ -d "/dev/dri" ]; then
                echo "  ✓ Hardware acceleration available"
            else
                echo "  ⚠ Hardware acceleration may not be available"
            fi
        fi

        # Check compositor performance
        echo "  • Compositor: $(echo ${WAYLAND_DISPLAY:-unknown})"
        echo "  • Backend: ${GDK_BACKEND:-auto}"

        return 0
    else
        echo "Not running on Wayland, skipping Wayland performance check"
        return 1
    fi
}

install_extension_helper() {
    local extension_id="$1"

    echo "Installing GNOME extension: $extension_id"

    # Try using gnome-extensions CLI if available
    if command -v gnome-extensions >/dev/null 2>&1; then
        echo "Use the following command to install:"
        echo "  gnome-extensions install $extension_id"
        echo "Or visit: https://extensions.gnome.org/extension/$extension_id/"
    else
        echo "Visit: https://extensions.gnome.org/ and search for the extension"
    fi
}

# Main function
main() {
    echo "=== GNOME Integration Setup for Claude Desktop ==="
    echo ""

    local gnome_version=$(get_gnome_version)

    if [ "$gnome_version" -eq 0 ]; then
        echo "GNOME not detected. This script is for GNOME desktop environment only."
        exit 1
    fi

    echo "GNOME version: $gnome_version"
    echo "Session type: ${XDG_SESSION_TYPE:-unknown}"
    echo ""

    check_gnome_extensions
    echo ""

    read -p "Set up GNOME integration for Claude Desktop? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_gnome_integration
        echo ""
    fi

    check_wayland_performance
    echo ""

    echo "🎉 GNOME integration check complete!"
    echo ""
    echo "For best Claude Desktop experience on GNOME:"
    echo "1. Install the AppIndicator Support extension for system tray"
    echo "2. Use 'Claude (Optimized)' from the applications menu"
    echo "3. Set CLAUDE_DEBUG=1 environment variable for troubleshooting"
}

# Export functions for sourcing
export -f get_gnome_version
export -f check_gnome_extensions
export -f setup_gnome_integration
export -f check_wayland_performance

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
