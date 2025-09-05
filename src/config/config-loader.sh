#!/bin/bash
# Configuration management system with schema validation

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/error-handler.sh"

# Global configuration variables
declare -gA CONFIG=()
declare -g CONFIG_FILE=""
declare -g CONFIG_SCHEMA=""
declare -g CONFIG_LOADED=false

# Initialize configuration system
init_config() {
    local config_file="${1:-}"
    local schema_file="${2:-}"
    local project_root
    project_root="$(dirname "${BASH_SOURCE[0]}")/../.."

    # Set default paths if not provided
    if [[ -z "$config_file" ]]; then
        config_file="$project_root/config/default.json"
    fi

    if [[ -z "$schema_file" ]]; then
        schema_file="$project_root/config/schema.json"
    fi

    CONFIG_FILE="$config_file"
    CONFIG_SCHEMA="$schema_file"

    # Load configuration
    load_config "$config_file" "$schema_file"
}

# Load configuration from JSON file
load_config() {
    local config_file="$1"
    local schema_file="$2"

    info "Loading configuration from: $config_file"

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "$config_file" 2>/dev/null; then
        error "Invalid JSON syntax in configuration file: $config_file"
        return 1
    fi

    # Validate against schema if available
    if [[ -f "$schema_file" ]] && command -v ajv >/dev/null 2>&1; then
        info "Validating configuration against schema"
        if ! ajv validate -s "$schema_file" -d "$config_file" 2>/dev/null; then
            warn "Configuration validation failed, but continuing anyway"
        fi
    else
        debug "Schema validation skipped (ajv not available or schema not found)"
    fi

    # Parse configuration into associative array
    parse_config "$config_file"
    CONFIG_LOADED=true

    info "Configuration loaded successfully"
}

# Parse JSON configuration into bash associative array
parse_config() {
    local config_file="$1"
    local temp_file
    temp_file=$(mktemp)

    # Convert JSON to key=value pairs using jq
    jq -r '
        def flatten:
            . as $in
            | reduce paths(scalars) as $p ({};
                . + { ($p | map(tostring) | join(".")): ($in | getpath($p)) }
            );
        flatten | to_entries[] | "\(.key)=\(.value)"
    ' "$config_file" > "$temp_file"

    # Load into CONFIG associative array
    while IFS='=' read -r key value; do
        # Handle boolean values
        case "$value" in
            true) value="true" ;;
            false) value="false" ;;
            null) value="" ;;
        esac
        CONFIG["$key"]="$value"
    done < "$temp_file"

    rm -f "$temp_file"
    debug "Parsed $(( ${#CONFIG[@]} )) configuration keys"
}

# Get configuration value
get_config() {
    local key="$1"
    local default_value="${2:-}"

    if [[ "$CONFIG_LOADED" != "true" ]]; then
        warn "Configuration not loaded, using default values"
        echo "$default_value"
        return 1
    fi

    if [[ -n "${CONFIG[$key]:-}" ]]; then
        echo "${CONFIG[$key]}"
    else
        debug "Configuration key not found: $key, using default: $default_value"
        echo "$default_value"
    fi
}

# Set configuration value (runtime only)
set_config() {
    local key="$1"
    local value="$2"

    CONFIG["$key"]="$value"
    debug "Set configuration: $key=$value"
}

# Get configuration as boolean
get_config_bool() {
    local key="$1"
    local default_value="${2:-false}"
    local value

    value=$(get_config "$key" "$default_value")

    case "$value" in
        true|1|yes|on) echo "true" ;;
        false|0|no|off|"") echo "false" ;;
        *) echo "$default_value" ;;
    esac
}

# Get configuration as integer
get_config_int() {
    local key="$1"
    local default_value="${2:-0}"
    local value

    value=$(get_config "$key" "$default_value")

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        debug "Invalid integer value for $key: $value, using default: $default_value"
        echo "$default_value"
    fi
}

# Get configuration as array (comma-separated or JSON array)
get_config_array() {
    local key="$1"
    local temp_file
    temp_file=$(mktemp)

    # Get all keys that start with the given prefix
    local array_keys=()
    for config_key in "${!CONFIG[@]}"; do
        if [[ "$config_key" =~ ^${key}\.[0-9]+$ ]]; then
            array_keys+=("$config_key")
        fi
    done

    # Sort by array index
    IFS=$'\n' array_keys=($(sort -V <<< "${array_keys[*]}"))

    # Output array values
    for array_key in "${array_keys[@]}"; do
        echo "${CONFIG[$array_key]}"
    done
}

# Merge configuration files
merge_config() {
    local base_config="$1"
    local override_config="$2"
    local output_file="${3:-}"

    if [[ ! -f "$base_config" ]]; then
        error "Base configuration file not found: $base_config"
        return 1
    fi

    if [[ ! -f "$override_config" ]]; then
        error "Override configuration file not found: $override_config"
        return 1
    fi

    info "Merging configurations: $base_config + $override_config"

    local merged_config
    merged_config=$(jq -s '.[0] * .[1]' "$base_config" "$override_config")

    if [[ -n "$output_file" ]]; then
        echo "$merged_config" > "$output_file"
        info "Merged configuration saved to: $output_file"
    else
        echo "$merged_config"
    fi
}

# Create configuration override file
create_user_config() {
    local user_config_file="$1"
    local template="${2:-minimal}"

    info "Creating user configuration file: $user_config_file"

    mkdir -p "$(dirname "$user_config_file")"

    case "$template" in
        minimal)
            cat > "$user_config_file" << 'EOF'
{
  "installer": {
    "log_level": "INFO"
  },
  "optimization": {
    "enable_wayland_optimizations": true
  }
}
EOF
            ;;
        wayland-optimized)
            cat > "$user_config_file" << 'EOF'
{
  "installer": {
    "log_level": "DEBUG"
  },
  "system": {
    "preferred_session": "wayland",
    "preferred_desktop": ["gnome"]
  },
  "optimization": {
    "enable_hardware_acceleration": true,
    "enable_wayland_optimizations": true,
    "enable_gpu_acceleration": true,
    "ozone_platform": "wayland",
    "electron_flags": [
      "--enable-features=UseOzonePlatform,VaapiVideoDecoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE",
      "--ozone-platform=wayland",
      "--enable-wayland-ime"
    ]
  },
  "dependencies": {
    "optional_packages": [
      "libva-utils",
      "vulkan-tools",
      "mesa-vulkan-drivers"
    ]
  }
}
EOF
            ;;
        *)
            error "Unknown template: $template"
            return 1
            ;;
    esac

    info "User configuration file created successfully"
}

# Validate configuration
validate_config() {
    local config_file="${1:-$CONFIG_FILE}"
    local schema_file="${2:-$CONFIG_SCHEMA}"

    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi

    if [[ ! -f "$schema_file" ]]; then
        warn "Schema file not found: $schema_file"
        return 0
    fi

    if ! command -v ajv >/dev/null 2>&1; then
        warn "ajv command not found, skipping schema validation"
        return 0
    fi

    info "Validating configuration against schema"

    if ajv validate -s "$schema_file" -d "$config_file"; then
        info "Configuration validation passed"
        return 0
    else
        error "Configuration validation failed"
        return 1
    fi
}

# Display configuration summary
show_config() {
    local filter="${1:-}"

    if [[ "$CONFIG_LOADED" != "true" ]]; then
        warn "Configuration not loaded"
        return 1
    fi

    info "Configuration Summary:"
    echo "======================"

    # Sort keys for consistent output
    local sorted_keys=()
    IFS=$'\n' sorted_keys=($(sort <<< "${!CONFIG[*]}"))

    for key in "${sorted_keys[@]}"; do
        if [[ -z "$filter" || "$key" =~ $filter ]]; then
            printf "%-30s: %s\n" "$key" "${CONFIG[$key]}"
        fi
    done
}

# Export configuration to environment variables
export_config_to_env() {
    local prefix="${1:-CLAUDE_}"

    if [[ "$CONFIG_LOADED" != "true" ]]; then
        warn "Configuration not loaded"
        return 1
    fi

    for key in "${!CONFIG[@]}"; do
        local env_key="${prefix}${key//\./_}"
        env_key=$(echo "$env_key" | tr '[:lower:]' '[:upper:]')
        export "$env_key"="${CONFIG[$key]}"
    done

    info "Configuration exported to environment variables with prefix: $prefix"
}

# Load site-specific configuration if available
load_site_config() {
    local site_config_paths=(
        "/etc/claude-desktop/config.json"
        "$HOME/.config/claude-desktop/config.json"
        "$PWD/claude-desktop.json"
    )

    for site_config in "${site_config_paths[@]}"; do
        if [[ -f "$site_config" ]]; then
            info "Found site-specific configuration: $site_config"

            # Create temporary merged config
            local temp_config
            temp_config=$(mktemp --suffix=.json)

            if merge_config "$CONFIG_FILE" "$site_config" "$temp_config"; then
                CONFIG_FILE="$temp_config"
                parse_config "$temp_config"
                info "Site-specific configuration merged successfully"
                break
            else
                warn "Failed to merge site-specific configuration: $site_config"
            fi
        fi
    done
}

# Export functions for use in other scripts
export -f init_config load_config parse_config get_config set_config
export -f get_config_bool get_config_int get_config_array merge_config
export -f create_user_config validate_config show_config export_config_to_env
export -f load_site_config
