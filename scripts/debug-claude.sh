#!/bin/bash
# Debug and testing utilities for Claude Desktop optimization
# Performance Optimization Implementation - Debug Tools

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

debug_header() {
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} Claude Desktop Debug & Performance Analysis${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo "Timestamp: $(date)"
    echo ""
}

debug_environment() {
    echo -e "${CYAN}🔍 Environment Analysis${NC}"
    echo "────────────────────────────────────────────────────────────────"

    echo "Desktop Environment:"
    echo "  XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-unset}"
    echo "  XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-unset}"
    echo "  DESKTOP_SESSION: ${DESKTOP_SESSION:-unset}"
    echo "  WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-unset}"
    echo "  DISPLAY: ${DISPLAY:-unset}"
    echo ""

    echo "Performance Variables:"
    echo "  GDK_BACKEND: ${GDK_BACKEND:-unset}"
    echo "  QT_QPA_PLATFORM: ${QT_QPA_PLATFORM:-unset}"
    echo "  GTK_USE_PORTAL: ${GTK_USE_PORTAL:-unset}"
    echo "  MOZ_ENABLE_WAYLAND: ${MOZ_ENABLE_WAYLAND:-unset}"
    echo "  ELECTRON_ARGS: ${ELECTRON_ARGS:-unset}"
    echo ""

    if command -v gnome-shell >/dev/null 2>&1; then
        echo "GNOME Version: $(gnome-shell --version 2>/dev/null || echo 'Unable to determine')"
    fi

    echo ""
}

debug_hardware() {
    echo -e "${CYAN}⚙️ Hardware Analysis${NC}"
    echo "────────────────────────────────────────────────────────────────"

    echo "CPU:"
    if [ -f "/proc/cpuinfo" ]; then
        echo "  Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')"
        echo "  Cores: $(nproc)"
    fi
    echo ""

    echo "Memory:"
    if [ -f "/proc/meminfo" ]; then
        local total_mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
        local avail_mem=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
        echo "  Total: ${total_mem}MB"
        echo "  Available: ${avail_mem}MB"
    fi
    echo ""

    echo "GPU:"
    if command -v lspci >/dev/null 2>&1; then
        local gpu_info=$(lspci | grep -i vga | head -1)
        if [ -n "$gpu_info" ]; then
            echo "  $gpu_info"
        else
            echo "  No VGA device found"
        fi
    else
        echo "  lspci not available"
    fi
    echo ""

    echo "Graphics Stack:"
    echo "  DRI devices: $(ls /dev/dri/ 2>/dev/null | wc -l) available"
    echo "  VAAPI support: $(command -v vainfo >/dev/null && echo 'Yes' || echo 'No')"
    echo "  Vulkan support: $(command -v vulkaninfo >/dev/null && echo 'Yes' || echo 'No')"

    if command -v glxinfo >/dev/null 2>&1; then
        local gl_version=$(glxinfo | grep "OpenGL version" | head -1 2>/dev/null || echo "Unknown")
        echo "  OpenGL: $gl_version"
    else
        echo "  OpenGL: glxinfo not available"
    fi
    echo ""
}

debug_claude_installation() {
    echo -e "${CYAN}📦 Claude Desktop Installation Analysis${NC}"
    echo "────────────────────────────────────────────────────────────────"

    local claude_dir="/usr/lib64/claude-desktop"
    local scripts_dir="$claude_dir/scripts"

    echo "Installation Status:"
    if [ -d "$claude_dir" ]; then
        echo -e "  Installation directory: ${GREEN}✓ Found${NC}"

        # Check main components
        [ -f "$claude_dir/electron/electron" ] && echo -e "  Electron binary: ${GREEN}✓ Found${NC}" || echo -e "  Electron binary: ${RED}✗ Missing${NC}"
        [ -f "$claude_dir/app.asar" ] && echo -e "  App bundle: ${GREEN}✓ Found${NC}" || echo -e "  App bundle: ${RED}✗ Missing${NC}"
        [ -d "$claude_dir/app.asar.unpacked" ] && echo -e "  Unpacked resources: ${GREEN}✓ Found${NC}" || echo -e "  Unpacked resources: ${RED}✗ Missing${NC}"

        # Check optimization scripts
        if [ -d "$scripts_dir" ]; then
            echo -e "  Optimization scripts: ${GREEN}✓ Directory found${NC}"
            [ -f "$scripts_dir/environment-detector.sh" ] && echo -e "    Environment detector: ${GREEN}✓ Found${NC}" || echo -e "    Environment detector: ${YELLOW}⚠ Missing${NC}"
            [ -f "$scripts_dir/electron-args-builder.sh" ] && echo -e "    Electron args builder: ${GREEN}✓ Found${NC}" || echo -e "    Electron args builder: ${YELLOW}⚠ Missing${NC}"
        else
            echo -e "  Optimization scripts: ${YELLOW}⚠ Directory missing${NC}"
        fi
    else
        echo -e "  Installation directory: ${RED}✗ Not found${NC}"
        echo "  Claude Desktop may not be installed"
    fi
    echo ""

    echo "Launcher Status:"
    if [ -f "/usr/bin/claude-desktop" ]; then
        echo -e "  Launcher script: ${GREEN}✓ Found${NC}"

        # Check if launcher is optimized
        if grep -q "SCRIPTS_DIR" /usr/bin/claude-desktop 2>/dev/null; then
            echo -e "  Launcher type: ${GREEN}✓ Optimized${NC}"
        else
            echo -e "  Launcher type: ${YELLOW}⚠ Basic (not optimized)${NC}"
        fi
    else
        echo -e "  Launcher script: ${RED}✗ Missing${NC}"
    fi
    echo ""
}

debug_performance() {
    echo -e "${CYAN}🚀 Performance Analysis${NC}"
    echo "────────────────────────────────────────────────────────────────"

    # Check if Claude is running
    local claude_pid=$(pgrep -f "claude-desktop" | head -1)
    if [ -n "$claude_pid" ]; then
        echo -e "  Claude Desktop: ${GREEN}✓ Running${NC} (PID: $claude_pid)"

        # Memory usage
        if [ -f "/proc/$claude_pid/status" ]; then
            local mem_usage=$(grep VmRSS /proc/$claude_pid/status | awk '{print $2 " " $3}')
            echo "  Memory usage: $mem_usage"
        fi

        # CPU usage (requires ps)
        if command -v ps >/dev/null 2>&1; then
            local cpu_usage=$(ps -p $claude_pid -o %cpu --no-headers 2>/dev/null)
            echo "  CPU usage: ${cpu_usage}%"
        fi

    else
        echo -e "  Claude Desktop: ${YELLOW}⚠ Not running${NC}"
    fi
    echo ""

    # Check system load
    if [ -f "/proc/loadavg" ]; then
        local load_avg=$(cat /proc/loadavg | cut -d' ' -f1-3)
        echo "  System load: $load_avg"
    fi
    echo ""

    # Performance recommendations
    echo "Performance Recommendations:"

    # Backend optimization
    if [ "$XDG_SESSION_TYPE" = "wayland" ] && [ "$GDK_BACKEND" = "x11" ]; then
        echo -e "  ${YELLOW}⚠${NC} Running X11 backend on Wayland (performance penalty)"
        echo "    Recommendation: Allow Wayland backend for better performance"
    elif [ "$XDG_SESSION_TYPE" = "wayland" ] && [ "$GDK_BACKEND" = "wayland" ]; then
        echo -e "  ${GREEN}✓${NC} Using native Wayland backend"
    fi

    # Hardware acceleration
    if [ -d "/dev/dri" ] && command -v vainfo >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Hardware acceleration available"
    else
        echo -e "  ${YELLOW}⚠${NC} Hardware acceleration may not be available"
        echo "    Recommendation: Install mesa-va-drivers or intel-media-driver"
    fi

    echo ""
}

debug_logs() {
    echo -e "${CYAN}📋 Log Analysis${NC}"
    echo "────────────────────────────────────────────────────────────────"

    local log_file="$HOME/claude-desktop-launcher.log"

    if [ -f "$log_file" ]; then
        echo -e "  Log file: ${GREEN}✓ Found${NC} ($log_file)"

        local log_size=$(stat -c%s "$log_file" 2>/dev/null)
        echo "  Log size: $((log_size / 1024))KB"

        local log_lines=$(wc -l < "$log_file" 2>/dev/null)
        echo "  Log lines: $log_lines"

        echo ""
        echo "Recent log entries (last 10 lines):"
        tail -n 10 "$log_file" 2>/dev/null | sed 's/^/    /'

        echo ""
        echo "Error summary:"
        local error_count=$(grep -i "error\|failed\|exception" "$log_file" 2>/dev/null | wc -l)
        local warning_count=$(grep -i "warning\|warn" "$log_file" 2>/dev/null | wc -l)

        echo "  Errors: $error_count"
        echo "  Warnings: $warning_count"

        if [ "$error_count" -gt 0 ]; then
            echo ""
            echo "Recent errors:"
            grep -i "error\|failed\|exception" "$log_file" 2>/dev/null | tail -5 | sed 's/^/    /'
        fi

    else
        echo -e "  Log file: ${YELLOW}⚠ Not found${NC}"
        echo "    Log will be created when Claude Desktop is launched"
    fi
    echo ""
}

run_benchmark() {
    echo -e "${CYAN}⏱️ Performance Benchmark${NC}"
    echo "────────────────────────────────────────────────────────────────"

    echo "Running Claude Desktop startup benchmark..."
    echo ""

    # Measure startup time
    local start_time=$(date +%s%N)

    # Launch Claude in background and measure time to window appearance
    timeout 30s claude-desktop --no-sandbox &
    local claude_pid=$!

    # Wait for window to appear (simplified check)
    local window_appeared=false
    for i in {1..30}; do
        if pgrep -f "claude-desktop" >/dev/null; then
            window_appeared=true
            break
        fi
        sleep 1
    done

    local end_time=$(date +%s%N)
    local startup_ms=$(( (end_time - start_time) / 1000000 ))

    # Clean up
    kill $claude_pid 2>/dev/null
    pkill -f "claude-desktop" 2>/dev/null

    if [ "$window_appeared" = true ]; then
        echo -e "  Startup time: ${GREEN}${startup_ms}ms${NC}"

        if [ $startup_ms -lt 3000 ]; then
            echo -e "  Performance: ${GREEN}Excellent${NC}"
        elif [ $startup_ms -lt 5000 ]; then
            echo -e "  Performance: ${GREEN}Good${NC}"
        elif [ $startup_ms -lt 8000 ]; then
            echo -e "  Performance: ${YELLOW}Fair${NC}"
        else
            echo -e "  Performance: ${RED}Poor${NC}"
        fi
    else
        echo -e "  Startup: ${RED}Failed to start within 30 seconds${NC}"
    fi

    echo ""
}

generate_report() {
    local report_file="$HOME/claude-desktop-debug-report-$(date +%Y%m%d-%H%M%S).txt"

    echo "Generating debug report: $report_file"

    {
        debug_header
        debug_environment
        debug_hardware
        debug_claude_installation
        debug_performance
        debug_logs
    } > "$report_file"

    echo -e "${GREEN}✓${NC} Debug report saved to: $report_file"
    echo ""
    echo "Share this report when asking for support."
}

# Usage information
usage() {
    echo "Claude Desktop Debug & Performance Tool"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  --env          Show environment analysis"
    echo "  --hardware     Show hardware analysis"
    echo "  --install      Show installation status"
    echo "  --performance  Show performance analysis"
    echo "  --logs         Show log analysis"
    echo "  --benchmark    Run performance benchmark"
    echo "  --report       Generate full debug report"
    echo "  --all          Show all debug information"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all                 # Full debug analysis"
    echo "  $0 --performance         # Performance analysis only"
    echo "  CLAUDE_DEBUG=1 $0 --all  # Extended debug mode"
}

# Main execution
main() {
    case "${1:---all}" in
        --env)
            debug_header
            debug_environment
            ;;
        --hardware)
            debug_header
            debug_hardware
            ;;
        --install)
            debug_header
            debug_claude_installation
            ;;
        --performance)
            debug_header
            debug_performance
            ;;
        --logs)
            debug_header
            debug_logs
            ;;
        --benchmark)
            debug_header
            run_benchmark
            ;;
        --report)
            generate_report
            ;;
        --all)
            debug_header
            debug_environment
            debug_hardware
            debug_claude_installation
            debug_performance
            debug_logs
            echo ""
            echo -e "${PURPLE}Run '$0 --benchmark' to test startup performance${NC}"
            echo -e "${PURPLE}Run '$0 --report' to generate a debug report${NC}"
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
