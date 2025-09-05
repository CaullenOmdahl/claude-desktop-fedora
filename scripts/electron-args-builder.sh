#!/bin/bash
# Dynamic Electron argument builder
# Claude Desktop Fedora Performance Optimization - Phase 2

get_gpu_info() {
    if command -v lspci >/dev/null 2>&1; then
        lspci | grep -i vga | head -1 | sed 's/.*: //'
    else
        echo "unknown"
    fi
}

get_gpu_vendor() {
    local gpu_info=$(get_gpu_info | tr '[:upper:]' '[:lower:]')
    if echo "$gpu_info" | grep -q nvidia; then
        echo "nvidia"
    elif echo "$gpu_info" | grep -q amd; then
        echo "amd"
    elif echo "$gpu_info" | grep -q intel; then
        echo "intel"
    else
        echo "unknown"
    fi
}

has_vaapi_support() {
    [ -d "/dev/dri" ] && command -v vainfo >/dev/null 2>&1
}

has_vulkan_support() {
    command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo >/dev/null 2>&1
}

get_memory_total() {
    if [ -f "/proc/meminfo" ]; then
        awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
    else
        echo "4096"  # Default fallback
    fi
}

calculate_memory_limits() {
    local total_mem=$(get_memory_total)
    local heap_size

    # Allocate heap size based on available memory
    if [ "$total_mem" -gt 16384 ]; then      # > 16GB
        heap_size=8192
    elif [ "$total_mem" -gt 8192 ]; then     # > 8GB
        heap_size=4096
    elif [ "$total_mem" -gt 4096 ]; then     # > 4GB
        heap_size=2048
    else                                      # <= 4GB
        heap_size=1024
    fi

    echo "$heap_size"
}

build_electron_args() {
    local backend="$1"
    local args=""

    # Platform-specific arguments
    case "$backend" in
        "wayland")
            args+="--ozone-platform=wayland "
            args+="--enable-features=UseOzonePlatform,WaylandWindowDecorations "

            # Wayland-specific optimizations
            if [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
                args+="--gtk-version=4 "
            fi
            ;;
        "x11")
            args+="--ozone-platform=x11 "
            ;;
    esac

    # Hardware acceleration based on GPU vendor
    local gpu_vendor=$(get_gpu_vendor)
    case "$gpu_vendor" in
        "nvidia")
            if has_vaapi_support; then
                args+="--enable-features=VaapiVideoDecoder,VaapiVideoEncoder "
            fi
            args+="--use-gl=desktop "
            ;;
        "amd"|"intel")
            if has_vaapi_support; then
                args+="--enable-features=VaapiVideoDecoder,VaapiVideoEncoder "
                args+="--enable-zero-copy "
            fi
            args+="--use-gl=desktop "
            ;;
        *)
            # Conservative settings for unknown GPUs
            args+="--use-gl=desktop "
            ;;
    esac

    # Vulkan support if available
    if has_vulkan_support; then
        args+="--enable-features=Vulkan "
    fi

    # Performance optimizations
    args+="--enable-gpu-rasterization "
    args+="--enable-native-gpu-memory-buffers "
    args+="--enable-oop-rasterization "

    # Memory optimizations
    local heap_size=$(calculate_memory_limits)
    args+="--memory-pressure-off "
    args+="--max_old_space_size=$heap_size "

    # Security - keep sandboxing enabled but optimize
    args+="--enable-sandbox "

    # Disable problematic features that cause issues on Linux
    args+="--disable-background-timer-throttling "
    args+="--disable-renderer-backgrounding "
    args+="--disable-backgrounding-occluded-windows "

    # Logging configuration
    args+="--enable-logging=file "
    args+="--log-level=INFO "

    # Performance tuning
    args+="--no-first-run "
    args+="--disable-default-apps "
    args+="--disable-extensions "

    echo "$args"
}

export_electron_args() {
    local backend="${GDK_BACKEND:-x11}"
    local args=$(build_electron_args "$backend")

    echo "Electron Configuration:" >&2
    echo "  Backend: $backend" >&2
    echo "  GPU Vendor: $(get_gpu_vendor)" >&2
    echo "  GPU Info: $(get_gpu_info)" >&2
    echo "  VAAPI Support: $(has_vaapi_support && echo 'Yes' || echo 'No')" >&2
    echo "  Vulkan Support: $(has_vulkan_support && echo 'Yes' || echo 'No')" >&2
    echo "  Memory Limit: $(calculate_memory_limits)MB" >&2
    echo "  Total Memory: $(get_memory_total)MB" >&2

    export ELECTRON_ARGS="$args"
}

# Debug function for troubleshooting performance issues
debug_electron_config() {
    echo "=== Electron Configuration Debug ==="
    echo "Backend: ${GDK_BACKEND:-x11}"
    echo "GPU Vendor: $(get_gpu_vendor)"
    echo "GPU Info: $(get_gpu_info)"
    echo "VAAPI Available: $(has_vaapi_support && echo 'Yes' || echo 'No')"
    echo "Vulkan Available: $(has_vulkan_support && echo 'Yes' || echo 'No')"
    echo "DRI Devices: $(ls /dev/dri/ 2>/dev/null || echo 'None')"
    echo "Memory Total: $(get_memory_total)MB"
    echo "Heap Size: $(calculate_memory_limits)MB"
    echo "Electron Args: $(build_electron_args "${GDK_BACKEND:-x11}")"
    echo "================================="
}

# Export functions for sourcing
export -f get_gpu_info
export -f get_gpu_vendor
export -f has_vaapi_support
export -f has_vulkan_support
export -f build_electron_args
export -f export_electron_args
export -f debug_electron_config
