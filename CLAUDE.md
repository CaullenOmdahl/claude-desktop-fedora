# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an intelligent installer system for Claude Desktop on Fedora Linux. The project provides a seamless, legally compliant way to build and install Claude Desktop directly from Anthropic's official Windows installer, with full Linux desktop integration and automatic update management.

## Build Commands

- **One-line install**: `curl -sSL https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install.sh | sudo bash`
- **Manual build**: `sudo ./build-fedora.sh`
- **Update**: `claude-desktop-installer`
- **Debug mode**: `CLAUDE_DEBUG=1 claude-desktop`
- **Force backend**: `CLAUDE_FORCE_BACKEND=wayland claude-desktop`

## Architecture

The intelligent build system consists of multiple layers:

### Core Build Pipeline (`build-fedora.sh`)

1. **Environment Validation**: Checks Fedora compatibility and installs dependencies
2. **Source Acquisition**: Downloads Anthropic's official Windows installer  
3. **Resource Extraction**: Unpacks installer using 7z and processes app.asar
4. **Cross-Platform Adaptation**: Replaces Windows native bindings with Linux equivalents
5. **Performance Optimization**: Bundles optimization scripts and Electron runtime
6. **Package Creation**: Builds native RPM with proper metadata and dependencies

### Key Components

- `install.sh` - Unified single-file installer with complete build pipeline
- `VERSION` - Semantic versioning for the installer system (current: 3.2.3)
- Native bindings replacement - Linux compatibility layer with keyboard mapping, notifications, system detection
- Icon extraction system - Uses `icotool` and ImageMagick for color-preserving icon conversion
- Window dragging fix - CSS injection for frameless window dragging support
- i18n resource handling - Proper locale file extraction and installation

### Cross-Platform Compatibility Layer

The system includes a sophisticated multi-file compatibility layer:

**Native Bindings Replacement** (`claude-native-improved.js`):
- Enhanced keyboard mapping for Linux (46 key definitions)
- Desktop environment detection (GNOME, KDE, XFCE, etc.)
- System tray support detection
- Native notification integration using `notify-send`
- Wayland vs X11 session detection
- Window state management and progress indication

**Performance Optimization Scripts**:
- **Environment Detection**: Automatically selects optimal backend based on desktop environment and session type
- **GPU Acceleration**: Configures hardware acceleration for NVIDIA, AMD, and Intel GPUs
- **Memory Management**: Dynamic heap sizing based on available system memory
- **Platform Integration**: Optimizes for Wayland or X11 sessions

### Installation Paths

- Application: `/usr/lib64/claude-desktop/`
- Bundled Electron: `/usr/lib64/claude-desktop/electron/`
- Launcher: `/usr/bin/claude-desktop`
- Desktop entry: `/usr/share/applications/claude-desktop.desktop`
- Icons: `/usr/share/icons/hicolor/*/apps/claude-desktop.png`
- MCP config: `~/.config/Claude/claude_desktop_config.json`
- Logs: `~/claude-desktop-launcher.log`
- Optimization scripts: `/usr/lib64/claude-desktop/scripts/`

## System Requirements

- Fedora 42+ (tested)
- x86_64 architecture
- Dependencies auto-installed: sqlite3, p7zip-plugins, icoutils, ImageMagick, nodejs, npm, rpm-build
- Optional: vulkaninfo, vainfo for hardware acceleration
- 4GB RAM minimum, 8GB recommended
- 200MB installation space, 2GB for building

## Development Workflow

### Testing and Debugging

- **Runtime logs**: Check `~/claude-desktop-launcher.log` for application issues
- **Debug mode**: Run `CLAUDE_DEBUG=1 claude-desktop` for verbose output  
- **Environment detection**: Scripts automatically detect optimal configuration
- **Manual backend override**: Use `CLAUDE_FORCE_BACKEND=wayland` or `CLAUDE_FORCE_BACKEND=x11`
- **Performance testing**: Monitor GPU usage and memory with system tools

### Build Process Details

The build system is complex and involves multiple stages:

1. **Dependency Resolution** (`build-fedora.sh:96-142`): Checks and installs system packages
2. **Electron Bundling** (`build-fedora.sh:144-166`): Downloads and extracts Electron v37.0.0
3. **Source Processing** (`build-fedora.sh:194-242`): Extracts Claude Windows installer  
4. **Asset Processing** (`build-fedora.sh:244-277`): Converts Windows icons to Linux formats
5. **App Modification** (`build-fedora.sh:279-351`): Unpacks, modifies, and repacks app.asar
6. **Native Binding Replacement** (`build-fedora.sh:308-336`): Installs Linux-compatible bindings
7. **Performance Integration** (`build-fedora.sh:382-402`): Copies optimization scripts
8. **RPM Creation** (`build-fedora.sh:484-556`): Builds final package with metadata

### File Modification Patterns

When modifying the build system (`install.sh`):
- **Window dragging fix** is applied at lines 214-228 (modifies `.vite/renderer/main_window/index.html`)
- **Native bindings** replacement at lines 230-318 (creates `claude-native.js`)
- **Icon processing** at lines 326-389 (uses `icotool` + ImageMagick with PNG32 format for color preservation)
- **i18n resources** copied at lines 205-212 (handles separate locale JSON files)

### Known Issues and Solutions

**v3.2.3 Improvements**:
1. **Window Dragging**: Fixed by adding CSS to make top 50px draggable via `body::before` pseudo-element
2. **Icon Colors**: Fixed by using `icotool` instead of `wrestool` and forcing PNG32 format with `-type TrueColorAlpha`
3. **Click Interaction**: All interactive elements have `pointer-events: auto` and `z-index: 9999999` to remain clickable
4. **Dynamic Content**: CSS respects Claude's `.nc-drag` and `.nc-no-drag` classes for runtime-loaded content

## Version Management & Git Workflow

This project uses independent semantic versioning (Major.Minor.Patch) in the `VERSION` file.

### Automatic Version Incrementing

**IMPORTANT**: Before making any git commit, always increment the version in the `VERSION` file:

1. **Read current version**: `cat VERSION`
2. **Increment appropriately**:
   - **Patch** (x.x.X+1): Bug fixes, small improvements, documentation updates
   - **Minor** (x.X+1.0): New features, compatibility updates, significant changes
   - **Major** (X+1.0.0): Breaking changes, major architecture updates
3. **Update VERSION file**: `echo "X.Y.Z" > VERSION`
4. **Commit changes**: Include version bump in commit

### Version Increment Guidelines

- **Patch increment** for:
  - Bug fixes and error corrections
  - Documentation updates
  - Minor UX improvements
  - Small code refactoring

- **Minor increment** for:
  - New features or functionality
  - Updated Claude Desktop compatibility
  - Enhanced native bindings
  - Significant installer improvements

- **Major increment** for:
  - Breaking changes to build process
  - Architecture redesigns
  - Compatibility breaking updates

### Git Commit Workflow

```bash
# 1. Check current version
cat VERSION

# 2. Increment version (example: 1.0.1 -> 1.0.2)
echo "1.0.2" > VERSION

# 3. Stage all changes including VERSION
git add .

# 4. Commit with descriptive message
git commit -m "Fix installer UX and increment to v1.0.2"
```

**Always include the version number in commit messages for tracking.**

### Compliance

This project builds from Anthropic's official installer rather than redistributing binaries:

- **No binary redistribution**: Users build locally from official sources
- **Installer-based approach**: Downloads and processes official Windows installer
- **Update detection**: Checks official sources for new versions
- **User-initiated builds**: All builds happen on user's system

The installer script handles version detection and update management automatically.

## Technical Implementation Details

### Cross-Platform Electron Integration

The system transforms a Windows Electron app into a native Linux package:

1. **App.asar Processing**: Uses `npx asar` to extract, modify, and repack application code
2. **Native Module Replacement**: Replaces `claude-native` Windows bindings with Linux equivalents
3. **Resource Asset Conversion**: Converts Windows icons to Linux hicolor theme format
4. **Desktop Integration**: Creates `.desktop` files and system integration
5. **Electron Bundling**: Packages Electron runtime to avoid dependency issues

### Performance Optimization Architecture

**Environment Detection System** (`scripts/environment-detector.sh`):
- Detects session type (Wayland vs X11) via `XDG_SESSION_TYPE`
- Identifies desktop environment from `XDG_CURRENT_DESKTOP`  
- Determines GNOME version for compatibility decisions
- Exports optimal `GDK_BACKEND` based on environment capabilities

**Hardware Acceleration System** (`scripts/electron-args-builder.sh`):
- GPU vendor detection via `lspci` parsing
- VAAPI support detection for Intel/AMD hardware acceleration
- Vulkan capability detection for enhanced graphics performance
- Dynamic memory allocation based on system RAM (`/proc/meminfo`)
- Platform-specific Electron argument generation

### Security and Sandboxing

The build maintains Electron's security model:
- Keeps sandboxing enabled (`--enable-sandbox`)
- Sets proper chrome-sandbox permissions (4755, root:root)
- Uses minimal security warnings while maintaining protection
- Preserves Electron's security boundaries while adding Linux compatibility

### Compliance Architecture

**No Binary Redistribution Model**:
- Downloads official Windows installer from Anthropic's servers
- Transforms installer locally on user's system  
- Never redistributes Claude Desktop binaries
- Maintains legal compliance through build-from-source approach
- Update mechanism checks official sources directly