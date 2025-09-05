#!/bin/bash
# Advanced logging system with structured output and debugging capabilities

# Global variables
declare -g LOG_LEVEL="${LOG_LEVEL:-INFO}"
declare -g LOG_FORMAT="${LOG_FORMAT:-standard}"
declare -g LOG_FILE="${LOG_FILE:-}"
declare -g LOG_COLORS="${LOG_COLORS:-true}"

# Log levels (numeric for comparison)
if [[ -z "${LOG_LEVELS[INFO]+x}" ]]; then
    declare -gA LOG_LEVELS=(
        [DEBUG]=0
        [INFO]=1
        [WARN]=2
        [ERROR]=3
        [FATAL]=4
    )
fi

# ANSI color codes
if [[ -z "${COLORS[INFO]+x}" ]]; then
    declare -gA COLORS=(
        [DEBUG]='\033[0;36m'    # Cyan
        [INFO]='\033[0;32m'     # Green
        [WARN]='\033[1;33m'     # Yellow
        [ERROR]='\033[0;31m'    # Red
        [FATAL]='\033[1;31m'    # Bold Red
        [RESET]='\033[0m'       # Reset
        [BOLD]='\033[1m'        # Bold
        [DIM]='\033[2m'         # Dim
    )
fi

# Initialize logging system
init_logger() {
    local log_level="${1:-INFO}"
    local log_file="${2:-}"
    local enable_colors="${3:-true}"

    LOG_LEVEL="$log_level"
    LOG_FILE="$log_file"
    LOG_COLORS="$enable_colors"

    # Create log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE" || {
            echo "Failed to create log file: $LOG_FILE" >&2
            return 1
        }
    fi
}

# Get timestamp in ISO format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Check if log level should be printed
should_log() {
    local level="$1"
    local current_level_num="${LOG_LEVELS[$LOG_LEVEL]:-1}"
    local message_level_num="${LOG_LEVELS[$level]:-1}"

    [[ $message_level_num -ge $current_level_num ]]
}

# Format log message
format_message() {
    local level="$1"
    local message="$2"
    local component="${3:-main}"
    local timestamp
    timestamp=$(get_timestamp)

    case "$LOG_FORMAT" in
        json)
            printf '{"timestamp":"%s","level":"%s","component":"%s","message":"%s"}\n' \
                "$timestamp" "$level" "$component" "$message"
            ;;
        structured)
            printf "[%s] [%s] [%s] %s\n" "$timestamp" "$level" "$component" "$message"
            ;;
        *)
            printf "[%s] %s: %s\n" "$timestamp" "$level" "$message"
            ;;
    esac
}

# Add color to message if enabled
colorize_message() {
    local level="$1"
    local message="$2"

    if [[ "$LOG_COLORS" == "true" ]] && [[ -t 2 ]]; then
        printf "%b%s%b" "${COLORS[$level]}" "$message" "${COLORS[RESET]}"
    else
        printf "%s" "$message"
    fi
}

# Core logging function
log_message() {
    local level="$1"
    local message="$2"
    local component="${3:-}"

    should_log "$level" || return 0

    local formatted_message
    formatted_message=$(format_message "$level" "$message" "$component")

    local colored_message
    colored_message=$(colorize_message "$level" "$formatted_message")

    # Output to stderr
    printf "%s\n" "$colored_message" >&2

    # Output to log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        printf "%s\n" "$formatted_message" >> "$LOG_FILE"
    fi
}

# Convenience functions
debug() { log_message "DEBUG" "$1" "$2"; }
info() { log_message "INFO" "$1" "$2"; }
warn() { log_message "WARN" "$1" "$2"; }
error() { log_message "ERROR" "$1" "$2"; }
fatal() { log_message "FATAL" "$1" "$2"; }

# Progress indicator
show_progress() {
    local message="$1"
    local step="${2:-}"
    local total="${3:-}"

    if [[ -n "$step" && -n "$total" ]]; then
        info "[$step/$total] $message"
    else
        info "$message"
    fi
}

# Error with exit
die() {
    fatal "$1" "$2"
    exit 1
}

# Log command execution
log_command() {
    local cmd="$1"
    local component="${2:-command}"

    debug "Executing: $cmd" "$component"

    if ! eval "$cmd"; then
        error "Command failed: $cmd" "$component"
        return 1
    fi

    debug "Command succeeded: $cmd" "$component"
}

# Structured logging for operations
log_operation() {
    local operation="$1"
    local status="$2"
    local details="${3:-}"
    local component="${4:-operation}"

    case "$status" in
        start)
            info "Starting: $operation" "$component"
            ;;
        success)
            info "Completed: $operation${details:+ - $details}" "$component"
            ;;
        error)
            error "Failed: $operation${details:+ - $details}" "$component"
            ;;
        *)
            info "$operation: $status${details:+ - $details}" "$component"
            ;;
    esac
}

# Export functions for use in other scripts
export -f init_logger get_timestamp should_log format_message colorize_message
export -f log_message debug info warn error fatal show_progress die log_command log_operation
