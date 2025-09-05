#!/bin/bash
# Main installer orchestration system

set -eE

# Source dependencies
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/error-handler.sh"
source "$SCRIPT_DIR/../utils/system-detection.sh"
source "$SCRIPT_DIR/../config/config-loader.sh"
source "$SCRIPT_DIR/../components/downloader.sh"
source "$SCRIPT_DIR/../components/builder.sh"
source "$SCRIPT_DIR/../components/optimizer.sh"
source "$SCRIPT_DIR/../components/integrator.sh"

# Global installer state
declare -g INSTALLER_VERSION=""
declare -g INSTALLATION_ID=""
declare -g TEMP_DIR=""
declare -g CLEANUP_REGISTERED=false

# Initialize installer
init_installer() {
    local config_file="${1:-}"

    # Generate unique installation ID
    INSTALLATION_ID="claude-$(date +%Y%m%d-%H%M%S)-$$"

    # Initialize components
    init_error_handler
    init_logger "INFO" "/tmp/claude-installer-${INSTALLATION_ID}.log"
    init_config "$config_file"

    # Get installer version from config
    INSTALLER_VERSION=$(get_config "installer.version" "3.0.0")

    # Set up temporary directory
    TEMP_DIR=$(get_config "build.temp_directory" "/tmp/claude-installer")
    TEMP_DIR="${TEMP_DIR}-${INSTALLATION_ID}"

    info "Claude Desktop Installer v$INSTALLER_VERSION"
    info "Installation ID: $INSTALLATION_ID"
    info "Temporary directory: $TEMP_DIR"

    # Register cleanup
    register_cleanup

    # Create temp directory
    mkdir -p "$TEMP_DIR"
}

# Register cleanup handlers
register_cleanup() {
    if [[ "$CLEANUP_REGISTERED" == "true" ]]; then
        return 0
    fi

    trap 'cleanup_installer' EXIT INT TERM
    CLEANUP_REGISTERED=true
    debug "Cleanup handlers registered"
}

# Cleanup installer resources
cleanup_installer() {
    local keep_temp
    keep_temp=$(get_config_bool "build.keep_temp_files" "false")

    if [[ "$keep_temp" == "false" && -d "$TEMP_DIR" ]]; then
        info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" || warn "Failed to remove temporary directory"
    elif [[ "$keep_temp" == "true" ]]; then
        info "Temporary files preserved at: $TEMP_DIR"
    fi
}

# Pre-installation validation
validate_installation() {
    info "Validating installation prerequisites"

    # System requirements check
    log_operation "system_requirements" "start"

    local required_os
    required_os=$(get_config "system.required_os" "linux")
    local required_dist
    required_dist=$(get_config "system.required_distribution" "fedora")
    local minimum_version
    minimum_version=$(get_config "system.minimum_version" "38")
    local required_arch
    required_arch=$(get_config "system.required_architecture" "x86_64")

    if ! check_requirements "${required_dist}${minimum_version}" "$required_arch"; then
        log_operation "system_requirements" "error" "System requirements not met"
        return 1
    fi

    log_operation "system_requirements" "success"

    # Dependencies check
    log_operation "dependencies" "start"

    local required_packages
    mapfile -t required_packages < <(get_config_array "dependencies.required_packages")

    if ! validate_prerequisites "${required_packages[@]}"; then
        log_operation "dependencies" "error" "Missing required dependencies"
        return 1
    fi

    log_operation "dependencies" "success"

    # System health check
    if ! check_system_health; then
        warn "System health issues detected, but continuing"
    fi

    info "Pre-installation validation completed successfully"
}

# Check for existing installation
check_existing_installation() {
    local binary_path
    binary_path=$(get_config "claude.binary_path" "/usr/bin/claude-desktop")
    local installation_path
    installation_path=$(get_config "claude.installation_path" "/usr/lib64/claude-desktop")

    if [[ -f "$binary_path" || -d "$installation_path" ]]; then
        info "Existing Claude Desktop installation detected"
        return 0
    else
        info "No existing installation found"
        return 1
    fi
}

# Install system dependencies
install_dependencies() {
    info "Installing system dependencies"
    log_operation "dependency_installation" "start"

    local package_manager
    package_manager=$(get_config "dependencies.package_manager" "auto")

    # Auto-detect package manager if needed
    if [[ "$package_manager" == "auto" ]]; then
        if command -v dnf >/dev/null 2>&1; then
            package_manager="dnf"
        elif command -v yum >/dev/null 2>&1; then
            package_manager="yum"
        else
            error "No supported package manager found"
            return 1
        fi
    fi

    # Get package lists
    local required_packages
    mapfile -t required_packages < <(get_config_array "dependencies.required_packages")
    local optional_packages
    mapfile -t optional_packages < <(get_config_array "dependencies.optional_packages")

    # Install required packages
    if [[ ${#required_packages[@]} -gt 0 ]]; then
        info "Installing required packages: ${required_packages[*]}"
        if ! safe_execute "sudo $package_manager install -y ${required_packages[*]}" "Install required packages"; then
            log_operation "dependency_installation" "error" "Failed to install required packages"
            return 1
        fi
    fi

    # Install optional packages (allow failures)
    if [[ ${#optional_packages[@]} -gt 0 ]]; then
        info "Installing optional packages: ${optional_packages[*]}"
        safe_execute "sudo $package_manager install -y ${optional_packages[*]}" "Install optional packages" "true"
    fi

    log_operation "dependency_installation" "success"
}

# Main installation workflow
perform_installation() {
    info "Starting Claude Desktop installation"
    log_operation "installation" "start"

    # Download Claude Desktop installer
    log_operation "download" "start"
    local installer_path
    installer_path="$TEMP_DIR/Claude-Setup.exe"

    local download_url
    download_url=$(get_config "claude.download_url")

    if ! download_claude "$download_url" "$installer_path"; then
        log_operation "download" "error"
        return 1
    fi

    log_operation "download" "success"

    # Build Linux package
    log_operation "build" "start"
    local package_path
    package_path="$TEMP_DIR/claude-desktop.rpm"

    if ! build_claude_package "$installer_path" "$package_path"; then
        log_operation "build" "error"
        return 1
    fi

    log_operation "build" "success"

    # Optimize for current system
    log_operation "optimization" "start"
    if ! optimize_claude_installation "$package_path"; then
        warn "Optimization failed, but continuing with installation"
    else
        log_operation "optimization" "success"
    fi

    # Install package
    log_operation "package_installation" "start"
    if ! safe_execute "sudo rpm -ivh '$package_path'" "Install Claude Desktop package"; then
        log_operation "package_installation" "error"
        return 1
    fi

    log_operation "package_installation" "success"

    # Desktop integration
    log_operation "integration" "start"
    if ! integrate_desktop_environment; then
        warn "Desktop integration partially failed"
    else
        log_operation "integration" "success"
    fi

    log_operation "installation" "success"
    info "Claude Desktop installation completed successfully"
}

# Update existing installation
perform_update() {
    info "Updating existing Claude Desktop installation"
    log_operation "update" "start"

    # Check current version
    local current_version
    if command -v claude-desktop >/dev/null 2>&1; then
        current_version=$(claude-desktop --version 2>/dev/null | grep -o '[0-9.]*' | head -1 || echo "unknown")
        info "Current version: $current_version"
    fi

    # Perform fresh installation (will upgrade existing)
    if perform_installation; then
        log_operation "update" "success"
        info "Claude Desktop updated successfully"
        return 0
    else
        log_operation "update" "error"
        return 1
    fi
}

# Uninstall Claude Desktop
perform_uninstall() {
    info "Uninstalling Claude Desktop"
    log_operation "uninstall" "start"

    # Remove package
    if rpm -q claude-desktop >/dev/null 2>&1; then
        safe_execute "sudo rpm -e claude-desktop" "Remove Claude Desktop package"
    fi

    # Remove user configuration (optional)
    local config_dir
    config_dir=$(get_config "claude.config_directory" "~/.config/Claude")
    config_dir="${config_dir/#\~/$HOME}"

    if [[ -d "$config_dir" ]]; then
        read -p "Remove user configuration directory ($config_dir)? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$config_dir"
            info "User configuration removed"
        fi
    fi

    # Clean up desktop integration
    cleanup_desktop_integration

    log_operation "uninstall" "success"
    info "Claude Desktop uninstalled successfully"
}

# Main entry point
main() {
    local action="${1:-install}"
    local config_file="${2:-}"

    # Initialize installer
    init_installer "$config_file"

    case "$action" in
        install)
            validate_installation
            install_dependencies
            perform_installation
            ;;
        update)
            validate_installation
            install_dependencies
            perform_update
            ;;
        uninstall)
            perform_uninstall
            ;;
        check)
            validate_installation
            if check_existing_installation; then
                info "Claude Desktop is installed"
                exit 0
            else
                info "Claude Desktop is not installed"
                exit 1
            fi
            ;;
        *)
            error "Unknown action: $action"
            echo "Usage: $0 {install|update|uninstall|check} [config-file]"
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
