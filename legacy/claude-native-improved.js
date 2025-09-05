/**
 * Enhanced Claude Native Bindings for Fedora 42
 * Provides improved Linux compatibility and Wayland support
 */

const os = require('os');
const { spawn } = require('child_process');

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

// Enhanced notification support for Fedora
function showNotification(title, body, icon = null) {
  try {
    const args = ['--urgency=normal'];
    if (title) args.push('--summary', title);
    if (body) args.push('--body', body);
    if (icon) args.push('--icon', icon);
    
    spawn('notify-send', args, { stdio: 'ignore' });
    return true;
  } catch (error) {
    console.warn('Native notification failed:', error.message);
    return false;
  }
}

// System tray detection for Fedora 42
function hasSystemTraySupport() {
  const desktop = getDesktopEnvironment();
  const session = getSessionType();
  
  // GNOME 42+ has limited system tray support
  if (desktop.includes('gnome')) {
    return false; // GNOME removed system tray by default
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

// Window state management
let windowStates = {
  isMaximized: false,
  isMinimized: false,
  isFullscreen: false
};

// Progress indication support
function setProgressBar(progress) {
  try {
    // Try to use desktop integration
    if (process.env.XDG_CURRENT_DESKTOP) {
      // Could integrate with desktop progress indicators
      console.log(`Progress: ${Math.round(progress * 100)}%`);
    }
    return true;
  } catch (error) {
    return false;
  }
}

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
    hasTraySupport: hasSystemTraySupport()
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
  
  // Notifications with enhanced Fedora support
  showNotification: (title, body, options = {}) => {
    return showNotification(title, body, options.icon);
  },
  
  // Progress indication
  setProgressBar: (progress) => setProgressBar(progress),
  clearProgressBar: () => setProgressBar(0),
  
  // System tray (enhanced detection)
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
  
  // Enhanced keyboard support
  KeyboardKey: Object.freeze(KeyboardKey),
  
  // Utility functions
  isWayland: () => getSessionType() === 'wayland',
  isX11: () => getSessionType() === 'x11',
  getDesktopEnvironment: getDesktopEnvironment,
  
  // Feature detection
  hasFeature: (feature) => {
    switch (feature) {
      case 'notifications': return true;
      case 'systemTray': return hasSystemTraySupport();
      case 'progressBar': return true;
      case 'windowEffects': return false;
      case 'globalShortcuts': return getSessionType() === 'x11'; // Wayland has restrictions
      default: return false;
    }
  }
};

// Export for compatibility
module.exports = ClaudeNativeBindings;

// Enhanced error handling
process.on('uncaughtException', (error) => {
  console.error('Claude Native Bindings Error:', error);
});

// Initialization logging
console.log(`Claude Native Bindings initialized for Fedora ${process.env.VERSION_ID || '42'}`);
console.log(`Desktop: ${getDesktopEnvironment()}, Session: ${getSessionType()}`);
console.log(`System Tray Support: ${hasSystemTraySupport()}`);