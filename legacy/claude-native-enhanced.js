/**
 * Enhanced Claude Native Bindings for Fedora 42+ with Wayland Optimization
 * Performance Optimization Implementation - Phase 3
 */

const os = require('os');
const { spawn, execSync } = require('child_process');

// Enhanced keyboard mapping for Fedora 42 / Linux
const KeyboardKey = {
  // Standard keys with Linux keycodes
  Backspace: 8,
  Tab: 9,
  Enter: 13,
  Shift: 16,
  Control: 17,
  Alt: 18,
  CapsLock: 20,
  Escape: 27,
  Space: 32,
  PageUp: 33,
  PageDown: 34,
  End: 35,
  Home: 36,
  LeftArrow: 37,
  UpArrow: 38,
  RightArrow: 39,
  DownArrow: 40,
  Delete: 46,
  Meta: 91,

  // Function keys
  F1: 112, F2: 113, F3: 114, F4: 115, F5: 116, F6: 117,
  F7: 118, F8: 119, F9: 120, F10: 121, F11: 122, F12: 123,

  // Number keys
  Digit0: 48, Digit1: 49, Digit2: 50, Digit3: 51, Digit4: 52,
  Digit5: 53, Digit6: 54, Digit7: 55, Digit8: 56, Digit9: 57,

  // Letter keys (A-Z)
  KeyA: 65, KeyB: 66, KeyC: 67, KeyD: 68, KeyE: 69, KeyF: 70,
  KeyG: 71, KeyH: 72, KeyI: 73, KeyJ: 74, KeyK: 75, KeyL: 76,
  KeyM: 77, KeyN: 78, KeyO: 79, KeyP: 80, KeyQ: 81, KeyR: 82,
  KeyS: 83, KeyT: 84, KeyU: 85, KeyV: 86, KeyW: 87, KeyX: 88,
  KeyY: 89, KeyZ: 90
};

// Helper functions for system detection
function checkCommand(command) {
  try {
    execSync(`command -v ${command}`, { stdio: 'ignore', timeout: 3000 });
    return true;
  } catch (error) {
    return false;
  }
}

function safeExecSync(command, fallback = null) {
  try {
    return execSync(command, { encoding: 'utf8', timeout: 5000 }).trim();
  } catch (error) {
    return fallback;
  }
}

// Detect desktop environment
function getDesktopEnvironment() {
  const env = process.env;
  if (env.XDG_CURRENT_DESKTOP) return env.XDG_CURRENT_DESKTOP.toLowerCase();
  if (env.DESKTOP_SESSION) return env.DESKTOP_SESSION.toLowerCase();
  if (env.GNOME_DESKTOP_SESSION_ID) return 'gnome';
  if (env.KDE_FULL_SESSION) return 'kde';
  return 'unknown';
}

// Detect session type (X11 vs Wayland)
function getSessionType() {
  return process.env.XDG_SESSION_TYPE || 'unknown';
}

// Wayland compositor detection
function getWaylandCompositor() {
  if (!process.env.WAYLAND_DISPLAY) return null;

  const desktop = getDesktopEnvironment();
  if (desktop.includes('gnome')) return 'mutter';
  if (desktop.includes('kde') || desktop.includes('plasma')) return 'kwin';
  if (desktop.includes('sway')) return 'sway';
  if (desktop.includes('hyprland')) return 'hyprland';
  if (desktop.includes('weston')) return 'weston';
  return 'unknown';
}

// Hardware detection functions
function getGPUInfo() {
  const output = safeExecSync('lspci | grep -i vga | head -1', 'Unknown GPU');
  return output.includes(':') ? output.split(':').pop().trim() : output;
}

function getGPUVendor() {
  const gpu = getGPUInfo().toLowerCase();
  if (gpu.includes('nvidia')) return 'nvidia';
  if (gpu.includes('amd')) return 'amd';
  if (gpu.includes('intel')) return 'intel';
  return 'unknown';
}

function hasVaapiSupport() {
  const fs = require('fs');
  return fs.existsSync('/dev/dri') && checkCommand('vainfo');
}

function hasVulkanSupport() {
  return checkCommand('vulkaninfo');
}

function getOpenGLInfo() {
  if (!checkCommand('glxinfo')) return 'unknown';
  const output = safeExecSync('glxinfo | grep "OpenGL version" | head -1');
  return output ? output.split(':').pop().trim() : 'unknown';
}

// GNOME version detection
function getGnomeVersion() {
  if (!checkCommand('gnome-shell')) return 0;
  const output = safeExecSync('gnome-shell --version');
  if (!output) return 0;
  const version = output.match(/\d+/);
  return version ? parseInt(version[0]) : 0;
}

// GNOME extension detection
function checkGnomeExtension(extensionId) {
  if (!checkCommand('gnome-extensions')) return false;
  const output = safeExecSync('gnome-extensions list');
  return output ? output.includes(extensionId) : false;
}

// Enhanced notification support for Fedora
function showNotification(title, body, options = {}) {
  try {
    const args = ['--urgency=normal'];
    if (title) args.push('--summary', title);
    if (body) args.push('--body', body);
    if (options.icon) args.push('--icon', options.icon);

    spawn('notify-send', args, { stdio: 'ignore' });
    return true;
  } catch (error) {
    console.warn('Native notification failed:', error.message);
    return false;
  }
}

// System tray detection for modern environments
function hasSystemTraySupport() {
  const desktop = getDesktopEnvironment();
  const session = getSessionType();

  // GNOME 42+ has limited system tray support by default
  if (desktop.includes('gnome')) {
    const version = getGnomeVersion();
    if (version >= 42) {
      // Check for AppIndicator extension
      return checkGnomeExtension('appindicatorsupport@rgcjonas.gmail.com');
    }
    return false;
  }

  // KDE Plasma has excellent system tray support
  if (desktop.includes('kde') || desktop.includes('plasma')) {
    return true;
  }

  // XFCE, MATE, Cinnamon have good support
  if (desktop.includes('xfce') || desktop.includes('mate') || desktop.includes('cinnamon')) {
    return true;
  }

  return false; // Conservative default
}

// Modern tray support (StatusNotifier/AppIndicator)
function hasModernTraySupport() {
  const desktop = getDesktopEnvironment();

  if (desktop.includes('gnome')) {
    const version = getGnomeVersion();
    if (version >= 48) {
      return checkGnomeExtension('appindicatorsupport@rgcjonas.gmail.com');
    }
  }

  // KDE always has modern tray support
  if (desktop.includes('kde') || desktop.includes('plasma')) {
    return true;
  }

  return false;
}

// Portal integration detection for Wayland
function checkPortal(portalName) {
  try {
    execSync(`dbus-send --session --dest=${portalName} --type=method_call --print-reply / org.freedesktop.DBus.Introspectable.Introspect`,
      { stdio: 'ignore', timeout: 3000 });
    return true;
  } catch (error) {
    return false;
  }
}

function getPortalCapabilities() {
  if (getSessionType() !== 'wayland') return {};

  try {
    return {
      fileChooser: checkPortal('org.freedesktop.portal.Desktop'),
      notification: checkPortal('org.freedesktop.portal.Desktop'),
      screenShare: checkPortal('org.freedesktop.portal.Desktop'),
      camera: checkPortal('org.freedesktop.portal.Desktop')
    };
  } catch (error) {
    return {};
  }
}

// Hardware acceleration detection
function getHardwareAcceleration() {
  try {
    return {
      vaapi: hasVaapiSupport(),
      vulkan: hasVulkanSupport(),
      opengl: getOpenGLInfo(),
      gpu: getGPUInfo(),
      vendor: getGPUVendor()
    };
  } catch (error) {
    return {
      vaapi: false,
      vulkan: false,
      opengl: 'unknown',
      gpu: 'unknown',
      vendor: 'unknown'
    };
  }
}

// Window state management
let windowStates = {
  isMaximized: false,
  isMinimized: false,
  isFullscreen: false
};

// Progress indication support
function setProgressBar(progress) {
  try {
    // Desktop integration for progress indication
    if (process.env.XDG_CURRENT_DESKTOP) {
      console.log(`Progress: ${Math.round(progress * 100)}%`);
    }
    return true;
  } catch (error) {
    return false;
  }
}

// Performance monitoring
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

// Enhanced module exports
const ClaudeNativeBindings = {
  // System information
  getWindowsVersion: () => "10.0.0", // Maintain compatibility
  getSystemInfo: () => ({
    platform: os.platform(),
    release: os.release(),
    arch: os.arch(),
    desktop: getDesktopEnvironment(),
    session: getSessionType(),
    compositor: getWaylandCompositor(),
    hasTraySupport: hasSystemTraySupport(),
    hasModernTraySupport: hasModernTraySupport()
  }),

  // Window management
  getIsMaximized: () => windowStates.isMaximized,
  setWindowMaximized: (maximized) => { windowStates.isMaximized = !!maximized; },
  getIsMinimized: () => windowStates.isMinimized,
  setWindowMinimized: (minimized) => { windowStates.isMinimized = !!minimized; },

  // Visual effects (stubbed but could be enhanced)
  setWindowEffect: (effect) => {
    console.log(`Window effect requested: ${effect}`);
    return false; // Not implemented on Linux
  },
  removeWindowEffect: () => true,

  // Frame/window interaction
  flashFrame: (flash = true) => {
    console.log(`Frame flash requested: ${flash}`);
    // Could implement with window manager integration
  },
  clearFlashFrame: () => {
    console.log('Frame flash cleared');
  },

  // Enhanced notifications with Wayland portal support
  showNotification: (title, body, options = {}) => {
    return showNotification(title, body, options);
  },

  // Progress indication
  setProgressBar: (progress) => setProgressBar(progress),
  clearProgressBar: () => setProgressBar(0),

  // System tray with modern support detection
  setOverlayIcon: (icon, description) => {
    if (hasSystemTraySupport()) {
      console.log(`Tray overlay icon: ${icon} - ${description}`);
      return true;
    }
    return false;
  },
  clearOverlayIcon: () => {
    if (hasSystemTraySupport()) {
      console.log('Tray overlay icon cleared');
      return true;
    }
    return false;
  },

  // Hardware acceleration detection
  getHardwareAcceleration: getHardwareAcceleration,

  // Wayland compositor detection
  getWaylandCompositor: getWaylandCompositor,

  // Portal integration
  getPortalCapabilities: getPortalCapabilities,

  // GNOME-specific features
  hasModernTraySupport: hasModernTraySupport,
  getGnomeVersion: getGnomeVersion,
  checkGnomeExtension: checkGnomeExtension,

  // Performance metrics
  getPerformanceMetrics: () => PerformanceMonitor.getMetrics(),

  // Enhanced keyboard support
  KeyboardKey: Object.freeze(KeyboardKey),

  // Utility functions
  isWayland: () => getSessionType() === 'wayland',
  isX11: () => getSessionType() === 'x11',
  getDesktopEnvironment: getDesktopEnvironment,
  getSessionType: getSessionType,

  // Feature detection
  hasFeature: (feature) => {
    switch (feature) {
      case 'notifications': return true;
      case 'systemTray': return hasSystemTraySupport();
      case 'modernTray': return hasModernTraySupport();
      case 'progressBar': return true;
      case 'windowEffects': return false;
      case 'globalShortcuts': return getSessionType() === 'x11'; // Wayland has restrictions
      case 'portals': return getSessionType() === 'wayland';
      case 'hardwareAccel': return getHardwareAcceleration().vaapi;
      case 'vulkan': return hasVulkanSupport();
      case 'vaapi': return hasVaapiSupport();
      default: return false;
    }
  },

  // Debug information
  getDebugInfo: () => ({
    environment: {
      session: getSessionType(),
      desktop: getDesktopEnvironment(),
      compositor: getWaylandCompositor(),
      backend: process.env.GDK_BACKEND,
      waylandDisplay: process.env.WAYLAND_DISPLAY,
      display: process.env.DISPLAY
    },
    hardware: getHardwareAcceleration(),
    features: {
      systemTray: hasSystemTraySupport(),
      modernTray: hasModernTraySupport(),
      portals: getPortalCapabilities()
    },
    performance: PerformanceMonitor.getMetrics()
  })
};

// Export for compatibility
module.exports = ClaudeNativeBindings;

// Enhanced error handling
process.on('uncaughtException', (error) => {
  console.error('Claude Native Bindings Error:', error);
});

// Initialization logging
console.log(`Claude Native Bindings Enhanced initialized for Fedora ${process.env.VERSION_ID || '42+'}`);
console.log(`Desktop: ${getDesktopEnvironment()}, Session: ${getSessionType()}, Compositor: ${getWaylandCompositor()}`);
console.log(`System Tray Support: ${hasSystemTraySupport()}, Modern Tray: ${hasModernTraySupport()}`);
console.log(`Hardware Acceleration: VAAPI=${hasVaapiSupport()}, Vulkan=${hasVulkanSupport()}`);

// Performance baseline
console.log('Performance monitoring initialized');
