#!/bin/bash
# Claude Desktop Fedora Installer v3.0.0 - Main Entry Point

set -eE

# Script metadata
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="Claude Desktop Installer"
readonly PROJECT_URL="https://github.com/CaullenOmdahl/claude-desktop-fedora"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Print colored output
print_color() {
    local color="$1"
    local message="$2"
    printf "${color}%s${NC}\n" "$message"
}

# Print banner
print_banner() {
    echo
    print_color "$BLUE" "╔══════════════════════════════════════════════════════════════╗"
    print_color "$BLUE" "║                $SCRIPT_NAME v$SCRIPT_VERSION                ║"
    print_color "$BLUE" "║              Intelligent Linux Desktop Integration           ║"
    print_color "$BLUE" "╚══════════════════════════════════════════════════════════════╝"
    echo
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ACTION]

Actions:
  install     Install Claude Desktop (default)
  update      Update existing installation
  uninstall   Remove Claude Desktop
  check       Check installation status

Options:
  -c, --config FILE    Use custom configuration file
  -v, --verbose        Enable verbose logging
  -q, --quiet          Suppress non-error output
  -h, --help           Show this help message
  --version           Show version information
  --dry-run           Show what would be done without executing

Examples:
  $0                              # Install with default settings
  $0 install --verbose            # Install with verbose logging
  $0 update                       # Update existing installation
  $0 --config /path/config.json   # Use custom configuration
  $0 uninstall                    # Remove Claude Desktop

For more information, visit: $PROJECT_URL
EOF
}

# Parse command line arguments
parse_arguments() {
    local action="install"
    local config_file=""
    local verbose=false
    local quiet=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            install|update|uninstall|check)
                action="$1"
                shift
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            --version)
                echo "$SCRIPT_NAME v$SCRIPT_VERSION"
                exit 0
                ;;
            *)
                print_color "$RED" "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Export parsed arguments
    export INSTALLER_ACTION="$action"
    export INSTALLER_CONFIG_FILE="$config_file"
    export INSTALLER_VERBOSE="$verbose"
    export INSTALLER_QUIET="$quiet"
    export INSTALLER_DRY_RUN="$dry_run"
}

# Quick system check
quick_system_check() {
    # Check if running on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        print_color "$RED" "Error: This installer only works on Linux systems"
        exit 1
    fi

    # Check if running on Fedora
    if [[ ! -f /etc/fedora-release ]]; then
        print_color "$YELLOW" "Warning: This installer is designed for Fedora Linux"
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_color "$BLUE" "Installation cancelled"
            exit 0
        fi
    fi

    # Check architecture
    if [[ "$(uname -m)" != "x86_64" ]]; then
        print_color "$RED" "Error: Only x86_64 architecture is supported"
        exit 1
    fi

    # Check for root privileges when needed
    if [[ "$INSTALLER_ACTION" != "check" && $EUID -eq 0 ]]; then
        print_color "$YELLOW" "Warning: Running as root. Some operations will be performed as regular user."
    fi
}

# Download and source core installer
bootstrap_installer() {
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"

    # Check if we have the full installer locally
    local installer_script="$script_dir/src/core/installer.sh"

    if [[ -f "$installer_script" ]]; then
        print_color "$GREEN" "Using local installer components"
        source "$installer_script"
        return 0
    fi

    # If not local, we're in the minimal installer mode
    print_color "$BLUE" "Downloading installer components..."

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    local repo_url="$PROJECT_URL"
    local branch="main"

    # Download minimal required files
    local base_url="https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/$branch"

    # Download core installer
    if command -v curl >/dev/null 2>&1; then
        curl -sSL "$base_url/legacy/install-main.sh" -o "$temp_dir/install-main.sh"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$base_url/legacy/install-main.sh" -O "$temp_dir/install-main.sh"
    else
        print_color "$RED" "Error: curl or wget is required for installation"
        exit 1
    fi

    if [[ ! -f "$temp_dir/install-main.sh" ]]; then
        print_color "$RED" "Error: Failed to download installer components"
        exit 1
    fi

    # Make executable and source
    chmod +x "$temp_dir/install-main.sh"
    source "$temp_dir/install-main.sh"
}

# Main installer entry point
main() {
    # Print banner
    print_banner

    # Parse arguments
    parse_arguments "$@"

    # Quick system validation
    quick_system_check

    # Set logging level based on verbosity
    if [[ "$INSTALLER_VERBOSE" == "true" ]]; then
        export LOG_LEVEL="DEBUG"
    elif [[ "$INSTALLER_QUIET" == "true" ]]; then
        export LOG_LEVEL="ERROR"
    else
        export LOG_LEVEL="INFO"
    fi

    # Show dry-run notice
    if [[ "$INSTALLER_DRY_RUN" == "true" ]]; then
        print_color "$YELLOW" "DRY RUN MODE - No changes will be made"
        export DRY_RUN="true"
    fi

    # Bootstrap full installer
    bootstrap_installer

    # Execute main installer with parsed arguments
    if command -v main_installer >/dev/null 2>&1; then
        main_installer "$INSTALLER_ACTION" "$INSTALLER_CONFIG_FILE"
    else
        # Fallback to legacy installer
        print_color "$BLUE" "Using legacy installer mode"
        main_legacy "$INSTALLER_ACTION"
    fi

    # Success message
    case "$INSTALLER_ACTION" in
        install)
            print_color "$GREEN" "✓ Claude Desktop installation completed successfully!"
            ;;
        update)
            print_color "$GREEN" "✓ Claude Desktop updated successfully!"
            ;;
        uninstall)
            print_color "$GREEN" "✓ Claude Desktop uninstalled successfully!"
            ;;
        check)
            # Status handled by installer
            ;;
    esac
}

# Legacy installer fallback
main_legacy() {
    local action="$1"

    case "$action" in
        install)
            print_color "$BLUE" "Starting installation using legacy installer..."
            ;;
        update)
            print_color "$BLUE" "Legacy installer doesn't support update, performing fresh install..."
            ;;
        uninstall)
            print_color "$RED" "Legacy installer doesn't support uninstall"
            exit 1
            ;;
        check)
            if command -v claude-desktop >/dev/null 2>&1; then
                print_color "$GREEN" "✓ Claude Desktop is installed"
                exit 0
            else
                print_color "$YELLOW" "✗ Claude Desktop is not installed"
                exit 1
            fi
            ;;
    esac
}

# Error handler for main script
handle_main_error() {
    local exit_code=$?
    print_color "$RED" "Installation failed with exit code: $exit_code"
    print_color "$BLUE" "For help and support, visit: $PROJECT_URL/issues"
    exit $exit_code
}

# Set up error handling
trap 'handle_main_error' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
