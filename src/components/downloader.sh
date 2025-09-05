#!/bin/bash
# Claude Desktop installer downloader with verification and caching

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/error-handler.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../config/config-loader.sh"

# Download configuration
declare -g DOWNLOAD_TIMEOUT=300
declare -g MAX_DOWNLOAD_RETRIES=3
declare -g CACHE_DIR="/tmp/claude-installer-cache"

# Initialize downloader
init_downloader() {
    DOWNLOAD_TIMEOUT=$(get_config_int "downloader.timeout" 300)
    MAX_DOWNLOAD_RETRIES=$(get_config_int "installer.max_retries" 3)

    mkdir -p "$CACHE_DIR"
    debug "Downloader initialized with timeout: ${DOWNLOAD_TIMEOUT}s, retries: $MAX_DOWNLOAD_RETRIES"
}

# Get latest Claude version from web
get_latest_claude_version() {
    local version_url
    version_url=$(get_config "claude.version_check_url" "https://claude.ai/download")
    local timeout=30

    info "Checking latest Claude version"
    debug "Version check URL: $version_url"

    # Try multiple methods to get version info
    local version=""

    # Method 1: Direct API call (if available)
    if command -v curl >/dev/null 2>&1; then
        version=$(curl -s --max-time $timeout -L "$version_url" 2>/dev/null | \
                  grep -oP 'version["\s]*:\s*["\s]*\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 2>/dev/null || echo "")
    fi

    # Method 2: Parse download page
    if [[ -z "$version" ]] && command -v curl >/dev/null 2>&1; then
        version=$(curl -s --max-time $timeout -L "$version_url" 2>/dev/null | \
                  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 2>/dev/null || echo "")
    fi

    # Method 3: Use cached version if available
    if [[ -z "$version" && -f "$CACHE_DIR/latest_version" ]]; then
        local cached_time
        cached_time=$(stat -c %Y "$CACHE_DIR/latest_version" 2>/dev/null || echo 0)
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - cached_time))

        # Use cached version if less than 1 hour old
        if [[ $age -lt 3600 ]]; then
            version=$(cat "$CACHE_DIR/latest_version" 2>/dev/null || echo "")
            debug "Using cached version: $version (age: ${age}s)"
        fi
    fi

    # Fallback version
    if [[ -z "$version" ]]; then
        version="1.0.0"
        warn "Could not determine latest version, using fallback: $version"
    fi

    # Cache the version
    echo "$version" > "$CACHE_DIR/latest_version" 2>/dev/null || true

    echo "$version"
}

# Get download URL for Claude installer
get_claude_download_url() {
    local version="${1:-latest}"
    local base_url
    base_url=$(get_config "claude.download_url")

    # If version is 'latest' or not specified, use configured URL
    if [[ "$version" == "latest" || -z "$version" ]]; then
        echo "$base_url"
    else
        # Try to construct versioned URL (may not work for all versions)
        echo "$base_url"
    fi
}

# Calculate file checksum
calculate_checksum() {
    local file_path="$1"
    local algorithm="${2:-sha256}"

    if [[ ! -f "$file_path" ]]; then
        error "File not found for checksum: $file_path"
        return 1
    fi

    case "$algorithm" in
        sha256)
            if command -v sha256sum >/dev/null 2>&1; then
                sha256sum "$file_path" | awk '{print $1}'
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "$file_path" | awk '{print $1}'
            else
                warn "No SHA256 utility available"
                return 1
            fi
            ;;
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$file_path" | awk '{print $1}'
            else
                warn "md5sum not available"
                return 1
            fi
            ;;
        *)
            error "Unknown checksum algorithm: $algorithm"
            return 1
            ;;
    esac
}

# Verify download integrity
verify_download() {
    local file_path="$1"
    local expected_checksum="${2:-}"
    local algorithm="${3:-sha256}"

    if [[ -z "$expected_checksum" ]]; then
        debug "No checksum provided, skipping verification"
        return 0
    fi

    info "Verifying download integrity"

    local actual_checksum
    actual_checksum=$(calculate_checksum "$file_path" "$algorithm")

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        info "Download verification successful"
        return 0
    else
        error "Download verification failed"
        error "Expected: $expected_checksum"
        error "Actual: $actual_checksum"
        return 1
    fi
}

# Download file with progress and verification
download_file() {
    local url="$1"
    local output_path="$2"
    local expected_checksum="${3:-}"
    local algorithm="${4:-sha256}"

    info "Downloading: $(basename "$output_path")"
    debug "URL: $url"
    debug "Output: $output_path"

    # Create output directory
    mkdir -p "$(dirname "$output_path")"

    # Check if HTTPS is enforced
    local use_https_only
    use_https_only=$(get_config_bool "security.use_https_only" "true")

    if [[ "$use_https_only" == "true" && ! "$url" =~ ^https:// ]]; then
        error "HTTPS-only mode enabled, but URL is not HTTPS: $url"
        return 1
    fi

    # Download with curl or wget
    local download_cmd=""
    local temp_file
    temp_file="${output_path}.tmp"

    if command -v curl >/dev/null 2>&1; then
        download_cmd="curl -L --max-time $DOWNLOAD_TIMEOUT --connect-timeout 30 -o '$temp_file' '$url'"
    elif command -v wget >/dev/null 2>&1; then
        download_cmd="wget --timeout=$DOWNLOAD_TIMEOUT --connect-timeout=30 -O '$temp_file' '$url'"
    else
        error "No download utility available (curl or wget required)"
        return 1
    fi

    # Perform download with retries
    local attempt=1
    while [[ $attempt -le $MAX_DOWNLOAD_RETRIES ]]; do
        show_progress "Downloading $(basename "$output_path")" "$attempt" "$MAX_DOWNLOAD_RETRIES"

        if eval "$download_cmd"; then
            info "Download completed successfully"
            break
        else
            warn "Download attempt $attempt failed"
            rm -f "$temp_file"

            if [[ $attempt -lt $MAX_DOWNLOAD_RETRIES ]]; then
                local delay=$((attempt * 5))
                warn "Retrying in ${delay}s..."
                sleep $delay
            fi
        fi

        ((attempt++))
    done

    if [[ ! -f "$temp_file" ]]; then
        error "Download failed after $MAX_DOWNLOAD_RETRIES attempts"
        return 1
    fi

    # Get file size
    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)

    if [[ $file_size -eq 0 ]]; then
        error "Downloaded file is empty"
        rm -f "$temp_file"
        return 1
    fi

    info "Downloaded $(( file_size / 1024 / 1024 ))MB"

    # Verify download if checksum provided
    if [[ -n "$expected_checksum" ]]; then
        local verify_downloads
        verify_downloads=$(get_config_bool "security.verify_downloads" "true")

        if [[ "$verify_downloads" == "true" ]]; then
            if ! verify_download "$temp_file" "$expected_checksum" "$algorithm"; then
                rm -f "$temp_file"
                return 1
            fi
        fi
    fi

    # Move to final location
    mv "$temp_file" "$output_path"

    info "File saved to: $output_path"
}

# Download Claude Desktop installer
download_claude() {
    local download_url="${1:-}"
    local output_path="${2:-}"
    local version="${3:-latest}"

    # Initialize downloader if not done
    if [[ ! -d "$CACHE_DIR" ]]; then
        init_downloader
    fi

    # Get download URL if not provided
    if [[ -z "$download_url" ]]; then
        download_url=$(get_claude_download_url "$version")
    fi

    # Set default output path if not provided
    if [[ -z "$output_path" ]]; then
        output_path="$CACHE_DIR/Claude-Setup.exe"
    fi

    # Check cache first
    local use_cache=true
    if [[ -f "$output_path" && "$use_cache" == "true" ]]; then
        local file_age
        file_age=$(stat -c %Y "$output_path" 2>/dev/null || echo 0)
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - file_age))

        # Use cached file if less than 1 day old
        if [[ $age -lt 86400 ]]; then
            info "Using cached installer (age: $((age / 3600))h)"
            return 0
        else
            info "Cached installer is outdated, downloading fresh copy"
        fi
    fi

    # Download the file
    log_operation "claude_download" "start"

    if download_file "$download_url" "$output_path"; then
        log_operation "claude_download" "success" "$(basename "$output_path")"
        return 0
    else
        log_operation "claude_download" "error"
        return 1
    fi
}

# Clean download cache
clean_cache() {
    local max_age_days="${1:-7}"

    if [[ ! -d "$CACHE_DIR" ]]; then
        return 0
    fi

    info "Cleaning download cache older than $max_age_days days"

    find "$CACHE_DIR" -type f -mtime +$max_age_days -delete 2>/dev/null || true

    # Remove empty directories
    find "$CACHE_DIR" -type d -empty -delete 2>/dev/null || true

    debug "Cache cleanup completed"
}

# Get download status/progress
get_download_info() {
    local url="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -sI --max-time 10 "$url" 2>/dev/null | grep -E "(Content-Length|Last-Modified|ETag)" || true
    fi
}

# Export functions for use in other scripts
export -f init_downloader get_latest_claude_version get_claude_download_url
export -f calculate_checksum verify_download download_file download_claude
export -f clean_cache get_download_info
