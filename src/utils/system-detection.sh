#!/bin/bash
# Advanced system detection and environment analysis

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Cache for system detection results
declare -gA SYSTEM_CACHE=()

# System detection with caching
get_system_info() {
    local key="$1"
    local force_refresh="${2:-false}"

    # Return cached result if available and not forcing refresh
    if [[ "$force_refresh" != "true" && -n "${SYSTEM_CACHE[$key]}" ]]; then
        echo "${SYSTEM_CACHE[$key]}"
        return 0
    fi

    local result
    case "$key" in
        os)
            result=$(detect_os)
            ;;
        distribution)
            result=$(detect_distribution)
            ;;
        version)
            result=$(detect_version)
            ;;
        architecture)
            result=$(detect_architecture)
            ;;
        desktop)
            result=$(detect_desktop_environment)
            ;;
        session)
            result=$(detect_session_type)
            ;;
        display_server)
            result=$(detect_display_server)
            ;;
        gpu)
            result=$(detect_gpu)
            ;;
        cpu)
            result=$(detect_cpu)
            ;;
        memory)
            result=$(detect_memory)
            ;;
        kernel)
            result=$(detect_kernel)
            ;;
        *)
            error "Unknown system info key: $key"
            return 1
            ;;
    esac

    # Cache the result
    SYSTEM_CACHE[$key]="$result"
    echo "$result"
}

# Detect operating system
detect_os() {
    local os
    os=$(uname -s)

    case "$os" in
        Linux)
            echo "linux"
            ;;
        Darwin)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        FreeBSD)
            echo "freebsd"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Detect Linux distribution
detect_distribution() {
    if [[ ! -f /etc/os-release ]]; then
        echo "unknown"
        return 1
    fi

    local distro
    distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "${distro:-unknown}"
}

# Detect distribution version
detect_version() {
    if [[ ! -f /etc/os-release ]]; then
        echo "unknown"
        return 1
    fi

    local version
    version=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "${version:-unknown}"
}

# Detect system architecture
detect_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        i386|i686)
            echo "i386"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l)
            echo "armv7l"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Detect desktop environment
detect_desktop_environment() {
    local desktop=""

    # Check environment variables first
    if [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
        desktop=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
    elif [[ -n "$DESKTOP_SESSION" ]]; then
        desktop=$(echo "$DESKTOP_SESSION" | tr '[:upper:]' '[:lower:]')
    elif [[ -n "$GDMSESSION" ]]; then
        desktop=$(echo "$GDMSESSION" | tr '[:upper:]' '[:lower:]')
    fi

    # Process detection
    if [[ -z "$desktop" ]]; then
        if pgrep -x "gnome-session" >/dev/null 2>&1; then
            desktop="gnome"
        elif pgrep -x "kded5" >/dev/null 2>&1; then
            desktop="kde"
        elif pgrep -x "xfce4-session" >/dev/null 2>&1; then
            desktop="xfce"
        elif pgrep -x "mate-session" >/dev/null 2>&1; then
            desktop="mate"
        elif pgrep -x "cinnamon-session" >/dev/null 2>&1; then
            desktop="cinnamon"
        elif pgrep -x "lxsession" >/dev/null 2>&1; then
            desktop="lxde"
        elif pgrep -x "i3" >/dev/null 2>&1; then
            desktop="i3"
        fi
    fi

    echo "${desktop:-unknown}"
}

# Detect session type
detect_session_type() {
    local session=""

    # Check XDG_SESSION_TYPE first
    if [[ -n "$XDG_SESSION_TYPE" ]]; then
        session="$XDG_SESSION_TYPE"
    # Check if running under Wayland
    elif [[ -n "$WAYLAND_DISPLAY" ]]; then
        session="wayland"
    # Check if running under X11
    elif [[ -n "$DISPLAY" ]]; then
        session="x11"
    # Check for loginctl
    elif command -v loginctl >/dev/null 2>&1; then
        session=$(loginctl show-session "$XDG_SESSION_ID" -p Type 2>/dev/null | cut -d= -f2)
    fi

    echo "${session:-unknown}"
}

# Detect display server
detect_display_server() {
    local display_server=""

    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        display_server="wayland"
    elif [[ -n "$DISPLAY" ]]; then
        display_server="x11"
    else
        # Check for running display servers
        if pgrep -x "Xorg" >/dev/null 2>&1; then
            display_server="x11"
        elif pgrep -f "wayland" >/dev/null 2>&1; then
            display_server="wayland"
        fi
    fi

    echo "${display_server:-unknown}"
}

# Detect GPU information
detect_gpu() {
    local gpu_info=""

    # Try lspci first
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci | grep -E "(VGA|3D|Display)" | head -1 | cut -d: -f3 | sed 's/^ //')
    fi

    # Try glxinfo as fallback
    if [[ -z "$gpu_info" ]] && command -v glxinfo >/dev/null 2>&1; then
        gpu_info=$(glxinfo | grep "OpenGL renderer" | cut -d: -f2 | sed 's/^ //')
    fi

    # Try nvidia-smi for NVIDIA GPUs
    if [[ -z "$gpu_info" ]] && command -v nvidia-smi >/dev/null 2>&1; then
        gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1)
    fi

    echo "${gpu_info:-unknown}"
}

# Detect CPU information
detect_cpu() {
    local cpu_info=""

    if [[ -f /proc/cpuinfo ]]; then
        cpu_info=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ //')
    fi

    echo "${cpu_info:-unknown}"
}

# Detect memory information
detect_memory() {
    local memory_gb=""

    if [[ -f /proc/meminfo ]]; then
        local memory_kb
        memory_kb=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        memory_gb=$((memory_kb / 1024 / 1024))
    fi

    echo "${memory_gb:-0}GB"
}

# Detect kernel version
detect_kernel() {
    local kernel
    kernel=$(uname -r)
    echo "$kernel"
}

# Check if system meets requirements
check_requirements() {
    local -a requirements=("$@")
    local -a missing_requirements=()

    for requirement in "${requirements[@]}"; do
        case "$requirement" in
            fedora*)
                local required_version="${requirement#fedora}"
                local current_distro
                current_distro=$(get_system_info "distribution")
                local current_version
                current_version=$(get_system_info "version")

                if [[ "$current_distro" != "fedora" ]]; then
                    missing_requirements+=("Requires Fedora, found: $current_distro")
                elif [[ -n "$required_version" ]] && (( current_version < required_version )); then
                    missing_requirements+=("Requires Fedora $required_version+, found: $current_version")
                fi
                ;;
            x86_64)
                local current_arch
                current_arch=$(get_system_info "architecture")
                if [[ "$current_arch" != "x86_64" ]]; then
                    missing_requirements+=("Requires x86_64 architecture, found: $current_arch")
                fi
                ;;
            wayland)
                local current_session
                current_session=$(get_system_info "session")
                if [[ "$current_session" != "wayland" ]]; then
                    missing_requirements+=("Requires Wayland session, found: $current_session")
                fi
                ;;
            gnome)
                local current_desktop
                current_desktop=$(get_system_info "desktop")
                if [[ "$current_desktop" != "gnome" ]]; then
                    missing_requirements+=("Requires GNOME desktop, found: $current_desktop")
                fi
                ;;
            *)
                warn "Unknown requirement: $requirement"
                ;;
        esac
    done

    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        error "System requirements not met:"
        printf '  - %s\n' "${missing_requirements[@]}" >&2
        return 1
    fi

    info "All system requirements met"
    return 0
}

# Get hardware capabilities
get_hardware_capabilities() {
    local -A capabilities=()

    # Check for hardware acceleration support
    if command -v vainfo >/dev/null 2>&1; then
        capabilities[vaapi]="available"
    else
        capabilities[vaapi]="not_available"
    fi

    # Check for Vulkan support
    if command -v vulkaninfo >/dev/null 2>&1; then
        capabilities[vulkan]="available"
    else
        capabilities[vulkan]="not_available"
    fi

    # Check for OpenGL support
    if command -v glxinfo >/dev/null 2>&1; then
        capabilities[opengl]="available"
    else
        capabilities[opengl]="not_available"
    fi

    # Output capabilities as JSON-like format
    local output="{"
    local first=true
    for key in "${!capabilities[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            output+=","
        fi
        output+="\"$key\":\"${capabilities[$key]}\""
    done
    output+="}"

    echo "$output"
}

# Comprehensive system report
generate_system_report() {
    local report_file="${1:-/tmp/system-report.txt}"

    info "Generating system report: $report_file"

    cat > "$report_file" << EOF
# System Report
Generated: $(date)

## Basic Information
OS: $(get_system_info "os")
Distribution: $(get_system_info "distribution")
Version: $(get_system_info "version")
Architecture: $(get_system_info "architecture")
Kernel: $(get_system_info "kernel")

## Desktop Environment
Desktop: $(get_system_info "desktop")
Session: $(get_system_info "session")
Display Server: $(get_system_info "display_server")

## Hardware
CPU: $(get_system_info "cpu")
Memory: $(get_system_info "memory")
GPU: $(get_system_info "gpu")

## Capabilities
$(get_hardware_capabilities)

## Environment Variables
XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-not set}
XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-not set}
WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-not set}
DISPLAY: ${DISPLAY:-not set}

## Package Manager
$(if command -v dnf >/dev/null 2>&1; then echo "dnf: available"; else echo "dnf: not available"; fi)
$(if command -v yum >/dev/null 2>&1; then echo "yum: available"; else echo "yum: not available"; fi)
$(if command -v rpm >/dev/null 2>&1; then echo "rpm: available"; else echo "rpm: not available"; fi)
EOF

    info "System report saved to: $report_file"
}

# Export functions for use in other scripts
export -f get_system_info detect_os detect_distribution detect_version
export -f detect_architecture detect_desktop_environment detect_session_type
export -f detect_display_server detect_gpu detect_cpu detect_memory detect_kernel
export -f check_requirements get_hardware_capabilities generate_system_report
