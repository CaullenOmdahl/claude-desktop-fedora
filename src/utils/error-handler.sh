#!/bin/bash
# Advanced error handling system with recovery mechanisms

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Global error handling configuration
declare -g ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/claude-installer-errors.log}"
declare -g ENABLE_RECOVERY="${ENABLE_RECOVERY:-true}"
declare -g MAX_RETRIES="${MAX_RETRIES:-3}"
declare -g RETRY_DELAY="${RETRY_DELAY:-5}"

# Error codes
if [[ -z "${ERROR_CODES[SUCCESS]+x}" ]]; then
    declare -gA ERROR_CODES=(
        [SUCCESS]=0
        [GENERAL_ERROR]=1
        [PERMISSION_ERROR]=2
        [NETWORK_ERROR]=3
        [DEPENDENCY_ERROR]=4
        [BUILD_ERROR]=5
        [CONFIGURATION_ERROR]=6
        [USER_ABORT]=130
    )
fi

# Initialize error handling
init_error_handler() {
    local error_log="${1:-$ERROR_LOG_FILE}"
    local enable_recovery="${2:-$ENABLE_RECOVERY}"

    ERROR_LOG_FILE="$error_log"
    ENABLE_RECOVERY="$enable_recovery"

    # Create error log directory
    mkdir -p "$(dirname "$ERROR_LOG_FILE")"

    # Set up trap handlers
    trap 'handle_exit $?' EXIT
    trap 'handle_interrupt' INT TERM
    trap 'handle_error $? $LINENO' ERR

    # Enable error tracing
    set -eE
}

# Handle script exit
handle_exit() {
    local exit_code="$1"

    if [[ $exit_code -eq 0 ]]; then
        debug "Script completed successfully"
    else
        error "Script exited with code: $exit_code"
        log_error_summary "$exit_code"
    fi
}

# Handle interrupt signals
handle_interrupt() {
    warn "Received interrupt signal, cleaning up..."
    cleanup_on_error
    exit "${ERROR_CODES[USER_ABORT]}"
}

# Handle errors with context
handle_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="${BASH_COMMAND:-unknown}"
    local function_name="${FUNCNAME[2]:-main}"
    local script_name="${BASH_SOURCE[2]:-$0}"

    local error_context="Script: $(basename "$script_name"), Function: $function_name, Line: $line_number"
    error "Command failed: '$command' ($error_context)"

    # Log detailed error information
    log_error_details "$exit_code" "$line_number" "$command" "$function_name" "$script_name"

    # Attempt recovery if enabled
    if [[ "$ENABLE_RECOVERY" == "true" ]]; then
        attempt_recovery "$exit_code" "$command"
    fi
}

# Log detailed error information
log_error_details() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    local function_name="$4"
    local script_name="$5"
    local timestamp
    timestamp=$(get_timestamp)

    cat >> "$ERROR_LOG_FILE" << EOF
========================================
Error Report: $timestamp
========================================
Exit Code: $exit_code
Script: $script_name
Function: $function_name
Line: $line_number
Command: $command
Environment:
  PWD: $PWD
  USER: $USER
  SHELL: $SHELL
  PATH: $PATH
System Info:
  OS: $(uname -s)
  Kernel: $(uname -r)
  Architecture: $(uname -m)
  Distribution: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
========================================

EOF
}

# Attempt error recovery
attempt_recovery() {
    local exit_code="$1"
    local failed_command="$2"

    info "Attempting error recovery..."

    case "$exit_code" in
        "${ERROR_CODES[PERMISSION_ERROR]}")
            recover_permission_error "$failed_command"
            ;;
        "${ERROR_CODES[NETWORK_ERROR]}")
            recover_network_error "$failed_command"
            ;;
        "${ERROR_CODES[DEPENDENCY_ERROR]}")
            recover_dependency_error "$failed_command"
            ;;
        *)
            warn "No recovery strategy available for exit code: $exit_code"
            ;;
    esac
}

# Recover from permission errors
recover_permission_error() {
    local command="$1"

    warn "Permission error detected. This may require sudo privileges."

    if command -v sudo >/dev/null 2>&1; then
        info "Attempting to run with sudo..."
        if sudo -n true 2>/dev/null; then
            info "Sudo access available, retrying command"
            return 0
        else
            error "Sudo access required but not available"
            return "${ERROR_CODES[PERMISSION_ERROR]}"
        fi
    else
        error "Sudo not available, cannot recover from permission error"
        return "${ERROR_CODES[PERMISSION_ERROR]}"
    fi
}

# Recover from network errors
recover_network_error() {
    local command="$1"

    warn "Network error detected. Checking connectivity..."

    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "No internet connectivity available"
        return "${ERROR_CODES[NETWORK_ERROR]}"
    fi

    info "Network connectivity confirmed, retrying after delay"
    sleep "$RETRY_DELAY"
    return 0
}

# Recover from dependency errors
recover_dependency_error() {
    local command="$1"

    warn "Dependency error detected. Checking package manager..."

    if command -v dnf >/dev/null 2>&1; then
        info "Attempting to install missing dependencies with dnf"
        return 0
    elif command -v yum >/dev/null 2>&1; then
        info "Attempting to install missing dependencies with yum"
        return 0
    else
        error "No supported package manager found"
        return "${ERROR_CODES[DEPENDENCY_ERROR]}"
    fi
}

# Retry mechanism with exponential backoff
retry_command() {
    local max_attempts="${1:-$MAX_RETRIES}"
    shift
    local command="$*"
    local attempt=1
    local delay="$RETRY_DELAY"

    while [[ $attempt -le $max_attempts ]]; do
        info "Attempt $attempt/$max_attempts: $command"

        if eval "$command"; then
            info "Command succeeded on attempt $attempt"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi

        ((attempt++))
    done

    error "Command failed after $max_attempts attempts: $command"
    return "${ERROR_CODES[GENERAL_ERROR]}"
}

# Safe command execution with error handling
safe_execute() {
    local command="$1"
    local description="${2:-$command}"
    local allow_failure="${3:-false}"

    info "Executing: $description"
    debug "Command: $command"

    if eval "$command"; then
        debug "Command succeeded: $description"
        return 0
    else
        local exit_code=$?

        if [[ "$allow_failure" == "true" ]]; then
            warn "Command failed but continuing: $description"
            return 0
        else
            error "Command failed: $description"
            return $exit_code
        fi
    fi
}

# Validate prerequisites
validate_prerequisites() {
    local -a required_commands=("$@")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing_commands[*]}"
        return "${ERROR_CODES[DEPENDENCY_ERROR]}"
    fi

    info "All required commands are available"
    return 0
}

# Cleanup function for error recovery
cleanup_on_error() {
    warn "Performing emergency cleanup..."

    # Remove temporary files
    find /tmp -name "claude-installer-*" -type f -mmin -60 -delete 2>/dev/null || true

    # Kill any hanging processes
    pkill -f "claude-installer" 2>/dev/null || true

    info "Emergency cleanup completed"
}

# Log error summary
log_error_summary() {
    local exit_code="$1"

    if [[ -f "$ERROR_LOG_FILE" ]]; then
        local error_count
        error_count=$(grep -c "Error Report:" "$ERROR_LOG_FILE" 2>/dev/null || echo "0")

        if [[ $error_count -gt 0 ]]; then
            error "Total errors in this session: $error_count"
            error "Detailed error log: $ERROR_LOG_FILE"
        fi
    fi
}

# Check system health
check_system_health() {
    local issues=()

    # Check disk space
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        issues+=("Low disk space: ${disk_usage}% used")
    fi

    # Check memory
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $mem_usage -gt 95 ]]; then
        issues+=("High memory usage: ${mem_usage}%")
    fi

    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count
    cpu_count=$(nproc)
    if (( $(echo "$load_avg > $cpu_count * 2" | bc -l) )); then
        issues+=("High system load: $load_avg (CPUs: $cpu_count)")
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        warn "System health issues detected:"
        printf '  - %s\n' "${issues[@]}" >&2
        return 1
    fi

    debug "System health check passed"
    return 0
}

# Export functions for use in other scripts
export -f init_error_handler handle_exit handle_interrupt handle_error
export -f log_error_details attempt_recovery retry_command safe_execute
export -f validate_prerequisites cleanup_on_error check_system_health
