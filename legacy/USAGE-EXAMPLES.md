# Claude Desktop Usage Examples & Advanced Configuration

## 🚀 Quick Start Examples

### Basic Usage (v2.0.0+)

```bash
# Standard launch (auto-optimized for your system)
claude-desktop

# Launch with specific backend
CLAUDE_FORCE_BACKEND=wayland claude-desktop
CLAUDE_FORCE_BACKEND=x11 claude-desktop

# Debug mode for troubleshooting
CLAUDE_DEBUG=1 claude-desktop
```

### Performance Optimization Examples

```bash
# High-performance mode (16GB+ RAM systems)
CLAUDE_MEMORY_LIMIT=8192 claude-desktop

# Conservative mode (4GB RAM systems)  
CLAUDE_MEMORY_LIMIT=1024 CLAUDE_DISABLE_HARDWARE_ACCEL=1 claude-desktop

# Battery-optimized mode
CLAUDE_FORCE_BACKEND=wayland CLAUDE_MEMORY_LIMIT=2048 claude-desktop
```

## 🔧 Environment Configuration

### Desktop Environment Specific

#### GNOME (Recommended Setup)
```bash
# Install GNOME integration
./scripts/gnome-integration.sh

# Launch with GNOME optimizations
CLAUDE_GNOME_INTEGRATION=1 claude-desktop

# Configure system tray (required for GNOME 42+)
# Install AppIndicator Support extension first
./scripts/gnome-integration.sh --setup-tray
```

#### KDE Plasma
```bash
# Launch with KDE optimizations (automatic)
claude-desktop

# Force Plasma theme integration
QT_QPA_PLATFORMTHEME=kde claude-desktop

# With custom Plasma shortcuts
claude-desktop --setup-kde-shortcuts
```

#### Sway/Hyprland
```bash
# Launch in floating mode (add to sway config)
for_window [app_id="Claude"] floating enable

# Or launch directly
swaymsg 'exec claude-desktop'

# With custom Waybar integration
claude-desktop --waybar-integration
```

## 📊 Debug and Monitoring Examples

### Performance Analysis

```bash
# Complete system analysis
./scripts/debug-claude.sh --all

# Quick performance check
./scripts/debug-claude.sh --performance

# Hardware acceleration test
./scripts/debug-claude.sh --hardware

# Startup benchmark
time claude-desktop --version
./scripts/debug-claude.sh --benchmark
```

### Monitoring Commands

```bash
# Real-time memory monitoring
watch -n 1 'ps aux | grep claude-desktop | grep -v grep'

# GPU utilization (NVIDIA)
watch -n 1 nvidia-smi

# System resource monitoring
htop -p $(pgrep claude-desktop)

# Wayland compositor monitoring (GNOME)
journalctl -f -u gdm | grep -i wayland
```

## 🎛️ Advanced Configuration

### Custom Launch Scripts

Create `~/.local/bin/claude-optimized`:
```bash
#!/bin/bash
# Custom Claude Desktop launcher with your preferred settings

# Set your preferred configuration
export CLAUDE_FORCE_BACKEND=wayland
export CLAUDE_MEMORY_LIMIT=4096
export GTK_THEME="Adwaita-dark"
export QT_QPA_PLATFORMTHEME=gtk3

# Optional debug logging
if [ "$1" = "--debug" ]; then
    export CLAUDE_DEBUG=1
    echo "Debug mode enabled - logs will be verbose"
fi

# Launch with optimizations
exec claude-desktop "$@"
```

Make it executable:
```bash
chmod +x ~/.local/bin/claude-optimized
claude-optimized  # Use your custom launcher
```

### Desktop File Customization

Create `~/.local/share/applications/claude-desktop-custom.desktop`:
```ini
[Desktop Entry]
Name=Claude (High Performance)
Comment=Claude Desktop optimized for performance
Exec=env CLAUDE_MEMORY_LIMIT=8192 CLAUDE_FORCE_BACKEND=wayland claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Development;AI;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
StartupNotify=true
Keywords=AI;Assistant;Claude;Performance;
X-GNOME-SingleWindow=true
```

### System Integration Examples

#### Systemd User Service (Auto-start)
Create `~/.config/systemd/user/claude-desktop.service`:
```ini
[Unit]
Description=Claude Desktop
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/claude-desktop --minimized
Environment="GDK_BACKEND=wayland"
Environment="CLAUDE_MEMORY_LIMIT=4096"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Enable and start:
```bash
systemctl --user daemon-reload
systemctl --user enable claude-desktop.service
systemctl --user start claude-desktop.service
```

## 🐛 Troubleshooting Examples

### Common Issues and Solutions

#### Issue: Slow Startup on Wayland
```bash
# Diagnose the issue
CLAUDE_DEBUG=1 time claude-desktop 2>&1 | grep -i "backend\|wayland\|startup"

# Try solutions
export CLAUDE_FORCE_BACKEND=wayland
export GDK_BACKEND=wayland  
claude-desktop

# Check if hardware acceleration is working
./scripts/debug-claude.sh --hardware | grep -i "vaapi\|vulkan"
```

#### Issue: High Memory Usage
```bash
# Monitor memory usage
./scripts/debug-claude.sh --performance

# Reduce memory allocation
export CLAUDE_MEMORY_LIMIT=2048
claude-desktop

# Check for memory leaks
valgrind --tool=memcheck --leak-check=full claude-desktop
```

#### Issue: System Tray Not Working
```bash
# Check system tray support
./scripts/debug-claude.sh --all | grep -i tray

# For GNOME - install AppIndicator extension
./scripts/gnome-integration.sh

# For other DEs - check configuration
echo "Desktop: $XDG_CURRENT_DESKTOP"
echo "Session: $XDG_SESSION_TYPE"
```

### Log Analysis Examples

```bash
# Real-time log monitoring
tail -f ~/claude-desktop-launcher.log

# Error filtering
grep -i "error\|failed\|exception" ~/claude-desktop-launcher.log

# Performance events
grep -i "startup\|backend\|hardware" ~/claude-desktop-launcher.log

# Last startup information
grep -A 10 -B 5 "Environment Detection Results" ~/claude-desktop-launcher.log | tail -20
```

## 🔬 Testing Different Configurations

### Backend Comparison Test
```bash
#!/bin/bash
# Compare performance between backends

echo "Testing X11 backend..."
time (CLAUDE_FORCE_BACKEND=x11 claude-desktop --version >/dev/null 2>&1)

echo "Testing Wayland backend..."  
time (CLAUDE_FORCE_BACKEND=wayland claude-desktop --version >/dev/null 2>&1)

echo "Testing auto-detection..."
time (claude-desktop --version >/dev/null 2>&1)
```

### Memory Usage Test
```bash
#!/bin/bash
# Test memory usage with different limits

for limit in 1024 2048 4096 8192; do
    echo "Testing with ${limit}MB limit..."
    CLAUDE_MEMORY_LIMIT=$limit claude-desktop &
    PID=$!
    sleep 10
    ps -o pid,rss,vsz,comm $PID
    kill $PID
    sleep 2
done
```

### Hardware Acceleration Test
```bash
#!/bin/bash
# Test hardware acceleration impact

echo "Testing without hardware acceleration..."
time (CLAUDE_DISABLE_HARDWARE_ACCEL=1 claude-desktop --version)

echo "Testing with hardware acceleration..."
time (claude-desktop --version)

# Check VAAPI functionality
if command -v vainfo >/dev/null; then
    echo "VAAPI test:"
    vainfo
fi
```

## 🎨 Theme and Appearance Examples

### Custom Themes
```bash
# Dark theme
export GTK_THEME="Adwaita-dark"
export QT_STYLE_OVERRIDE="Adwaita-Dark"
claude-desktop

# High contrast theme
export GTK_THEME="HighContrast" 
claude-desktop

# Custom theme integration
export GTK_THEME="MyCustomTheme"
export QT_QPA_PLATFORMTHEME=gtk3
claude-desktop
```

### DPI and Scaling
```bash
# Force specific DPI
export GDK_DPI_SCALE=1.5
export QT_SCALE_FACTOR=1.5
claude-desktop

# Integer scaling for sharp display
export GDK_SCALE=2
export QT_SCALE_FACTOR=2
claude-desktop

# Fractional scaling (GNOME)
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
claude-desktop
```

## 📱 Integration Examples

### Browser Integration
```bash
# Register Claude as handler for claude:// URLs
xdg-mime default claude-desktop.desktop x-scheme-handler/claude

# Test URL handling
xdg-open "claude://chat/new"
```

### File Manager Integration
Create `~/.local/share/file-manager/actions/claude-desktop.desktop`:
```ini
[Desktop Entry]
Type=Action
Name=Analyze with Claude
Icon=claude-desktop
Profiles=profile-one;

[X-Action-Profile profile-one]
MimeTypes=text/plain;text/markdown;application/pdf;
Exec=claude-desktop --analyze %f
Name=Analyze document with Claude Desktop
```

### Shell Integration
Add to `~/.bashrc` or `~/.zshrc`:
```bash
# Claude Desktop aliases
alias claude='claude-desktop'
alias claude-debug='CLAUDE_DEBUG=1 claude-desktop'
alias claude-perf='./scripts/debug-claude.sh --performance'

# Quick performance check
claude-status() {
    if pgrep -f claude-desktop >/dev/null; then
        echo "Claude Desktop is running"
        ./scripts/debug-claude.sh --performance
    else
        echo "Claude Desktop is not running"
    fi
}
```

## 🚀 Advanced Usage Patterns

### Development Workflow
```bash
# Development mode with hot reloading
CLAUDE_DEBUG=1 CLAUDE_DEV_MODE=1 claude-desktop

# With custom user data directory
CLAUDE_USER_DATA_DIR="$HOME/.config/Claude-dev" claude-desktop

# Isolated testing instance
CLAUDE_PROFILE="testing" claude-desktop --user-data-dir=/tmp/claude-test
```

### Multi-Monitor Setup
```bash
# Force Claude to specific monitor
DISPLAY=:0.1 claude-desktop  # Second monitor on X11

# Or use Wayland-aware positioning
claude-desktop --monitor=DP-2  # If supported by compositor
```

### Remote Access
```bash
# X11 forwarding over SSH
ssh -X user@remote-host
claude-desktop

# Wayland forwarding (experimental)
ssh user@remote-host
WAYLAND_DISPLAY=wayland-1 claude-desktop
```

---

**See also:**
- [PERFORMANCE.md](PERFORMANCE.md) - Performance optimization guide
- [WAYLAND.md](WAYLAND.md) - Wayland-specific features
- [PLAN.md](PLAN.md) - Implementation details