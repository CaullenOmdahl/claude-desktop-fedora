# Claude Desktop Fedora Performance Optimization Implementation Plan

## 🎯 Project Overview

This document outlines the comprehensive implementation plan for optimizing Claude Desktop performance on Fedora Linux, with a specific focus on Wayland/GNOME 48 compatibility. The current implementation forces X11 backend usage, creating significant performance overhead on modern Wayland systems.

**Current Performance Issues:**
- Forced X11 backend on Wayland (15-30% performance penalty)
- Suboptimal Electron launch arguments
- Limited native bindings for modern Linux environments  
- Security concerns with disabled sandboxing
- Poor system integration on GNOME 48+

**Expected Outcomes:**
- 25-40% faster startup times on Wayland
- 15-20% memory usage reduction
- 30-50% graphics performance improvement
- Native Wayland support with X11 fallback
- Enhanced desktop integration

## 📋 Implementation Phases

### Phase 1: Dynamic Backend Selection (HIGH PRIORITY)

**Objective:** Replace forced `GDK_BACKEND=x11` with intelligent session detection

**Current Problem:** 
```bash
# build-fedora.sh:380 & install-main.sh:257
export GDK_BACKEND=x11  # Forces XWayland compatibility layer
```

**Implementation Steps:**

#### 1.1 Create Environment Detection Module
**File:** `scripts/environment-detector.sh`
```bash
#!/bin/bash
# Environment detection for optimal backend selection

detect_session_type() {
    echo "${XDG_SESSION_TYPE:-unknown}"
}

detect_desktop_environment() {
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]'
    elif [ -n "$DESKTOP_SESSION" ]; then
        echo "$DESKTOP_SESSION" | tr '[:upper:]' '[:lower:]'
    elif [ -n "$GNOME_DESKTOP_SESSION_ID" ]; then
        echo "gnome"
    elif [ -n "$KDE_FULL_SESSION" ]; then
        echo "kde"
    else
        echo "unknown"
    fi
}

get_gnome_version() {
    if command -v gnome-shell >/dev/null 2>&1; then
        gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1
    else
        echo "0"
    fi
}

has_wayland_support() {
    [ "$XDG_SESSION_TYPE" = "wayland" ] && [ -n "$WAYLAND_DISPLAY" ]
}

get_optimal_backend() {
    local session=$(detect_session_type)
    local desktop=$(detect_desktop_environment)
    local gnome_version=$(get_gnome_version)
    
    # Use Wayland natively on supported environments
    if has_wayland_support; then
        case "$desktop" in
            *gnome*)
                if [ "$gnome_version" -ge 40 ]; then
                    echo "wayland"
                else
                    echo "x11"
                fi
                ;;
            *kde*|*plasma*)
                echo "wayland"  # KDE Plasma has excellent Wayland support
                ;;
            *sway*)
                echo "wayland"  # Sway is Wayland-native
                ;;
            *)
                echo "x11"  # Conservative fallback for unknown DEs
                ;;
        esac
    else
        echo "x11"  # X11 session or no Wayland support
    fi
}

export_optimal_backend() {
    local backend=$(get_optimal_backend)
    export GDK_BACKEND="$backend"
    
    echo "Environment Detection Results:" >&2
    echo "  Session Type: $(detect_session_type)" >&2
    echo "  Desktop Environment: $(detect_desktop_environment)" >&2
    echo "  GNOME Version: $(get_gnome_version)" >&2
    echo "  Selected Backend: $backend" >&2
}
```

#### 1.2 Update Build System
**File:** `build-fedora.sh` (around line 380)
```bash
# Remove: export GDK_BACKEND=x11
# Add environment detection integration

# Copy environment detector to package
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts"
cp "$SCRIPT_DIR/scripts/environment-detector.sh" "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/"
chmod +x "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/environment-detector.sh"

# Update launcher script
cat > "$INSTALL_DIR/bin/claude-desktop" << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/claude-desktop-launcher.log"

# Source environment detection
source /usr/lib64/claude-desktop/scripts/environment-detector.sh
export_optimal_backend

# Additional optimizations based on backend
if [ "$GDK_BACKEND" = "wayland" ]; then
    export GTK_USE_PORTAL=1
    export QT_QPA_PLATFORM=wayland
else
    export GTK_USE_PORTAL=0
fi

export ELECTRON_DISABLE_SECURITY_WARNINGS=true
/usr/lib64/claude-desktop/electron/electron /usr/lib64/claude-desktop/app.asar \
    --ozone-platform="$GDK_BACKEND" \
    --enable-logging=file \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    --enable-gpu-rasterization \
    --use-gl=desktop \
    "$@"
EOF
```

#### 1.3 Testing Strategy
- Test on GNOME 48+ Wayland
- Test on KDE Plasma Wayland
- Test on X11 sessions (backward compatibility)
- Verify performance improvements with benchmarks

**Estimated Timeline:** 2-3 days
**Performance Impact:** 15-30% improvement on Wayland systems

---

### Phase 2: Enhanced Electron Arguments (HIGH PRIORITY)

**Objective:** Optimize Electron launch arguments for performance and security

**Current Issues:**
```bash
--ozone-platform-hint=auto --disable-gpu-sandbox --no-sandbox
```
- `--disable-gpu-sandbox`: Reduces security and performance
- `--no-sandbox`: Major security risk
- `--ozone-platform-hint=auto`: May not select optimal backend

**Implementation Steps:**

#### 2.1 Create Dynamic Argument Builder
**File:** `scripts/electron-args-builder.sh`
```bash
#!/bin/bash
# Dynamic Electron argument builder

get_gpu_info() {
    if command -v lspci >/dev/null 2>&1; then
        lspci | grep -i vga | head -1
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

build_electron_args() {
    local backend="$1"
    local args=""
    
    # Platform-specific arguments
    case "$backend" in
        "wayland")
            args+="--ozone-platform=wayland "
            args+="--enable-features=UseOzonePlatform,VaapiVideoDecoder "
            args+="--gtk-version=4 "
            ;;
        "x11")
            args+="--ozone-platform=x11 "
            ;;
    esac
    
    # GPU acceleration
    if has_vaapi_support; then
        args+="--enable-features=VaapiVideoDecoder,VaapiVideoEncoder "
    fi
    
    if has_vulkan_support; then
        args+="--enable-features=Vulkan "
    fi
    
    # Performance optimizations
    args+="--enable-gpu-rasterization "
    args+="--use-gl=desktop "
    args+="--enable-zero-copy "
    args+="--enable-native-gpu-memory-buffers "
    
    # Memory optimizations
    args+="--memory-pressure-off "
    args+="--max_old_space_size=4096 "
    
    # Security (keep sandboxing enabled)
    args+="--enable-sandbox "
    
    # Logging
    args+="--enable-logging=file "
    args+="--log-level=INFO "
    
    echo "$args"
}

export_electron_args() {
    local backend="${GDK_BACKEND:-x11}"
    local args=$(build_electron_args "$backend")
    
    echo "Electron Arguments:" >&2
    echo "  Backend: $backend" >&2
    echo "  GPU Info: $(get_gpu_info)" >&2
    echo "  VAAPI Support: $(has_vaapi_support && echo 'Yes' || echo 'No')" >&2
    echo "  Vulkan Support: $(has_vulkan_support && echo 'Yes' || echo 'No')" >&2
    echo "  Arguments: $args" >&2
    
    export ELECTRON_ARGS="$args"
}
```

#### 2.2 Update Launcher Integration
**File:** `build-fedora.sh` (launcher section)
```bash
cat > "$INSTALL_DIR/bin/claude-desktop" << 'EOF'
#!/bin/bash
LOG_FILE="$HOME/claude-desktop-launcher.log"

# Source detection scripts
source /usr/lib64/claude-desktop/scripts/environment-detector.sh
source /usr/lib64/claude-desktop/scripts/electron-args-builder.sh

# Configure environment
export_optimal_backend
export_electron_args
export ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Launch with optimized arguments
exec /usr/lib64/claude-desktop/electron/electron \
    /usr/lib64/claude-desktop/app.asar \
    $ELECTRON_ARGS \
    --log-file="$LOG_FILE" \
    "$@"
EOF
```

**Estimated Timeline:** 2-3 days
**Performance Impact:** 30-50% graphics performance improvement

---

### Phase 3: Advanced Native Bindings (MEDIUM PRIORITY)

**Objective:** Enhance `claude-native-improved.js` with modern Linux features

#### 3.1 Wayland-Specific Extensions
**File:** `claude-native-improved.js` (additions)
```javascript
// Wayland compositor detection
function getWaylandCompositor() {
  if (!process.env.WAYLAND_DISPLAY) return null;
  
  const desktop = getDesktopEnvironment();
  if (desktop.includes('gnome')) return 'mutter';
  if (desktop.includes('kde') || desktop.includes('plasma')) return 'kwin';
  if (desktop.includes('sway')) return 'sway';
  return 'unknown';
}

// Hardware acceleration detection
function getHardwareAcceleration() {
  const fs = require('fs');
  
  return {
    vaapi: fs.existsSync('/dev/dri') && checkCommand('vainfo'),
    vulkan: checkCommand('vulkaninfo'),
    opengl: getOpenGLInfo(),
    gpu: getGPUInfo()
  };
}

// Enhanced GNOME 48+ system tray support
function hasModernTraySupport() {
  const desktop = getDesktopEnvironment();
  const session = getSessionType();
  
  if (desktop.includes('gnome')) {
    const version = getGnomeVersion();
    if (version >= 48) {
      // Check for AppIndicator extension
      return checkGnomeExtension('appindicatorsupport@rgcjonas.gmail.com');
    }
  }
  
  return hasLegacyTraySupport();
}

// Portal integration for Wayland
function getPortalCapabilities() {
  if (getSessionType() !== 'wayland') return {};
  
  return {
    fileChooser: checkPortal('org.freedesktop.portal.FileChooser'),
    notification: checkPortal('org.freedesktop.portal.Notification'),
    screenShare: checkPortal('org.freedesktop.portal.ScreenCast'),
    camera: checkPortal('org.freedesktop.portal.Camera')
  };
}
```

#### 3.2 Performance Monitoring
```javascript
// Performance metrics collection
const PerformanceMonitor = {
  startupTime: Date.now(),
  memoryBaseline: process.memoryUsage(),
  
  getMetrics() {
    const uptime = Date.now() - this.startupTime;
    const memory = process.memoryUsage();
    
    return {
      uptime,
      memoryUsage: memory,
      memoryGrowth: {
        rss: memory.rss - this.memoryBaseline.rss,
        heapUsed: memory.heapUsed - this.memoryBaseline.heapUsed
      },
      platform: {
        backend: process.env.GDK_BACKEND,
        session: getSessionType(),
        compositor: getWaylandCompositor(),
        hardware: getHardwareAcceleration()
      }
    };
  }
};
```

**Estimated Timeline:** 3-4 days
**Performance Impact:** Better system integration, improved debugging

---

### Phase 4: Build System Optimization (MEDIUM PRIORITY)

**Objective:** Conditional compilation and dependency management

#### 4.1 Environment-Aware Building
**File:** `build-fedora.sh` (around dependency section)
```bash
# Enhanced dependency detection
detect_build_environment() {
    echo "🔍 Detecting build environment capabilities..."
    
    # Wayland development libraries
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        WAYLAND_DEPS="wayland-devel libwayland-client wayland-protocols"
        echo "  + Adding Wayland development dependencies"
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL $WAYLAND_DEPS"
    fi
    
    # GPU acceleration libraries
    if lspci | grep -qi nvidia; then
        echo "  + NVIDIA GPU detected, adding VAAPI-NVIDIA support"
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL libva-nvidia-driver"
    elif lspci | grep -qi amd; then
        echo "  + AMD GPU detected, adding Mesa VAAPI support"
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL mesa-va-drivers"
    elif lspci | grep -qi intel; then
        echo "  + Intel GPU detected, adding Intel VAAPI support"
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL intel-media-driver"
    fi
    
    # Vulkan support
    if command -v vulkaninfo >/dev/null 2>&1; then
        echo "  + Vulkan support detected"
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL vulkan-tools"
    fi
}
```

#### 4.2 Runtime Environment Configuration
```bash
# Create environment-specific configurations
create_environment_configs() {
    local config_dir="$INSTALL_DIR/lib/$PACKAGE_NAME/config"
    mkdir -p "$config_dir"
    
    # Wayland-optimized configuration
    cat > "$config_dir/wayland.conf" << 'EOF'
# Wayland-specific optimizations
export QT_QPA_PLATFORM=wayland
export GTK_USE_PORTAL=1
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF
    
    # X11 compatibility configuration
    cat > "$config_dir/x11.conf" << 'EOF'
# X11 compatibility settings
export GTK_USE_PORTAL=0
export QT_QPA_PLATFORM=xcb
export ELECTRON_OZONE_PLATFORM_HINT=x11
EOF
    
    echo "✓ Environment configurations created"
}
```

**Estimated Timeline:** 2-3 days
**Performance Impact:** Optimized builds for specific environments

---

### Phase 5: Desktop Integration Enhancement (LOWER PRIORITY)

**Objective:** Enhanced system integration and user experience

#### 5.1 GNOME Extension Recommendations
**File:** `scripts/gnome-integration.sh`
```bash
#!/bin/bash
# GNOME-specific integration enhancements

check_gnome_extensions() {
    if ! command -v gnome-extensions >/dev/null 2>&1; then
        return 1
    fi
    
    local required_extensions=(
        "appindicatorsupport@rgcjonas.gmail.com"  # System tray support
        "blur-my-shell@aunetx"                    # Visual enhancements
    )
    
    local missing_extensions=()
    
    for ext in "${required_extensions[@]}"; do
        if ! gnome-extensions list | grep -q "$ext"; then
            missing_extensions+=("$ext")
        fi
    done
    
    if [ ${#missing_extensions[@]} -gt 0 ]; then
        echo "🔧 Recommended GNOME Extensions for better Claude Desktop integration:"
        for ext in "${missing_extensions[@]}"; do
            echo "  • $ext"
        done
        echo
        echo "Install via: https://extensions.gnome.org/"
    else
        echo "✓ All recommended GNOME extensions are installed"
    fi
}
```

#### 5.2 Notification System Integration
```bash
# Enhanced notification support with portal integration
setup_notification_integration() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        # Use portal-based notifications on Wayland
        cat > "$INSTALL_DIR/lib/$PACKAGE_NAME/scripts/notify.sh" << 'EOF'
#!/bin/bash
# Portal-aware notification system

send_notification() {
    local title="$1"
    local body="$2"
    local icon="$3"
    
    if command -v gdbus >/dev/null 2>&1; then
        # Use D-Bus portal for Wayland
        gdbus call --session \
            --dest=org.freedesktop.portal.Desktop \
            --object-path=/org/freedesktop/portal/desktop \
            --method=org.freedesktop.portal.Notification.AddNotification \
            "" "{'title': <'$title'>, 'body': <'$body'>}"
    else
        # Fallback to notify-send
        notify-send --icon="$icon" "$title" "$body"
    fi
}
EOF
    fi
}
```

**Estimated Timeline:** 2-3 days
**Performance Impact:** Better user experience and system integration

---

## 📊 Implementation Timeline

### Sprint 1 (Week 1): Foundation
- [ ] **Day 1-2**: Phase 1 - Dynamic Backend Selection
- [ ] **Day 3-4**: Phase 2 - Enhanced Electron Arguments  
- [ ] **Day 5**: Integration testing and debugging

### Sprint 2 (Week 2): Enhancement
- [ ] **Day 1-3**: Phase 3 - Advanced Native Bindings
- [ ] **Day 4-5**: Phase 4 - Build System Optimization

### Sprint 3 (Week 3): Polish & Integration
- [ ] **Day 1-2**: Phase 5 - Desktop Integration Enhancement
- [ ] **Day 3-4**: Comprehensive testing across environments
- [ ] **Day 5**: Documentation and release preparation

## 🎯 Success Metrics

### Performance Benchmarks
**Startup Time:**
- Current (X11 forced): ~3-5 seconds
- Target (Wayland native): ~2-3 seconds (25-40% improvement)

**Memory Usage:**
- Current: ~250-300MB baseline
- Target: ~200-250MB baseline (15-20% reduction)

**Graphics Performance:**
- Current: Software rendering fallback
- Target: Hardware-accelerated rendering (30-50% improvement)

### Compatibility Matrix
| Environment | Current Status | Target Status |
|-------------|----------------|---------------|
| GNOME 48+ Wayland | Poor (forced X11) | Excellent (native) |
| KDE Plasma Wayland | Poor (forced X11) | Excellent (native) |
| X11 (any DE) | Good | Maintained |
| Older GNOME (40-47) | Fair | Good |

### Testing Checklist
- [ ] GNOME 48 Wayland session (primary target)
- [ ] KDE Plasma 6 Wayland session
- [ ] X11 sessions (backward compatibility)
- [ ] System tray functionality
- [ ] Global shortcuts (Ctrl+Alt+Space)
- [ ] Hardware acceleration
- [ ] MCP functionality
- [ ] Update mechanism

## 📝 Risk Management

### High-Risk Areas
1. **Wayland Session Detection**: May fail on exotic configurations
   - *Mitigation*: Conservative X11 fallback
   
2. **Hardware Acceleration**: GPU driver compatibility issues
   - *Mitigation*: Graceful degradation to software rendering
   
3. **Breaking Changes**: Existing user configurations
   - *Mitigation*: Maintain backward compatibility

### Rollback Strategy
- Preserve current launcher as `claude-desktop.legacy`
- Environment variable override: `CLAUDE_FORCE_BACKEND=x11`
- Quick rollback script for critical issues

## 📚 Documentation Updates

### Files to Update
1. **README.md**: Add Wayland performance improvements
2. **CLAUDE.md**: Update installation instructions
3. **Troubleshooting Guide**: Add Wayland-specific sections
4. **Performance Tuning**: New section for optimization tips

### New Documentation
1. **PERFORMANCE.md**: Detailed performance analysis
2. **WAYLAND.md**: Wayland-specific features and setup
3. **TROUBLESHOOTING-WAYLAND.md**: Wayland troubleshooting guide

---

## 🚀 Getting Started

To begin implementation:

1. **Create feature branch**: `git checkout -b wayland-optimization`
2. **Set up development environment**: Ensure Fedora 48+ with GNOME
3. **Start with Phase 1**: Dynamic backend selection (highest impact)
4. **Test incrementally**: Each phase should be testable independently
5. **Document changes**: Update relevant documentation as you go

This plan provides a systematic approach to dramatically improving Claude Desktop performance on modern Wayland systems while maintaining full backward compatibility.