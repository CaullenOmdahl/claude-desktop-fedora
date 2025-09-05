# Claude Desktop for Fedora Linux

[![Version](https://img.shields.io/badge/version-3.1.1-blue.svg)](https://github.com/CaullenOmdahl/claude-desktop-fedora/releases)
[![License](https://img.shields.io/badge/license-MIT%2FApache-green.svg)](LICENSE)
[![Fedora](https://img.shields.io/badge/fedora-38%2B-blue.svg)](https://getfedora.org/)
[![Wayland](https://img.shields.io/badge/wayland-optimized-green.svg)](https://wayland.freedesktop.org/)

A streamlined, single-file installer for Claude Desktop on Fedora Linux with native Wayland support and advanced performance optimizations.

## ✨ Features

- **🚀 One-line Installation**: Simple, automated installation process
- **📄 Single-file Installer**: Everything in one self-contained script
- **🖥️ Wayland Optimized**: Native Wayland support with automatic backend detection
- **⚡ Performance Enhanced**: Hardware acceleration, GPU optimization, and native bindings
- **🎯 GNOME Integration**: Deep integration with GNOME Shell and desktop environment
- **📦 Smart Package Management**: Automatic dependency resolution and RPM packaging
- **🔄 Update Management**: Built-in update detection and seamless upgrades
- **🛡️ Security Focused**: Builds from official sources, no binary redistribution

## 🚀 Quick Start

### One-Line Install (with cache-busting)

```bash
curl -sSL "https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install.sh?$(date +%s)" | sudo bash
```

### Alternative One-Line Install (using wget)

```bash
wget -qO- "https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install.sh?$(date +%s)" | sudo bash
```

### Manual Installation
```bash
git clone https://github.com/CaullenOmdahl/claude-desktop-fedora.git
cd claude-desktop-fedora
chmod +x install.sh
sudo ./install.sh
```

### Troubleshooting Cache Issues

If you're getting an old version of the installer due to caching:

```bash
# Force refresh with cache-busting parameter
curl -sSL "https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install.sh?$(date +%s)" | sudo bash

# Or clear curl's cache
rm -rf ~/.cache/curl

# Or use wget with no-cache
wget --no-cache -qO- https://raw.githubusercontent.com/CaullenOmdahl/claude-desktop-fedora/main/install.sh | sudo bash
```

### Advanced Usage
```bash
# Install with custom configuration
./install.sh --config /path/to/config.json

# Update existing installation
./install.sh update

# Uninstall
./install.sh uninstall

# Check installation status
./install.sh check

# Verbose installation
./install.sh install --verbose
```

## 🏗️ Architecture

The v3.0 refactor introduces a completely modular architecture:

```
src/
├── core/           # Core installer orchestration
│   └── installer.sh
├── components/     # Modular components
│   ├── downloader.sh
│   ├── builder.sh
│   ├── optimizer.sh
│   └── integrator.sh
├── utils/          # Utility modules
│   ├── logger.sh
│   ├── error-handler.sh
│   └── system-detection.sh
└── config/         # Configuration system
    └── config-loader.sh

config/             # Configuration schemas
├── schema.json
└── default.json

scripts/            # Installation scripts
├── installers/
├── optimizers/
└── system/
```

## ⚙️ System Requirements

- **OS**: Fedora 38+ (tested on Fedora 42)
- **Architecture**: x86_64 
- **Desktop**: GNOME (primary), KDE (supported)
- **Display**: Wayland (preferred), X11 (fallback)
- **Memory**: 4GB+ recommended
- **Storage**: 500MB free space

## 🔧 Configuration

The installer uses a flexible JSON-based configuration system:

### Default Configuration
```bash
# View current configuration
cat config/default.json

# Create custom user configuration
cp config/default.json ~/.config/claude-desktop/config.json
```

### Key Configuration Options
- **Wayland/X11 Backend**: Auto-detection with manual override
- **Hardware Acceleration**: VAAPI, Vulkan, OpenGL support
- **Performance Tuning**: Electron optimization flags
- **Desktop Integration**: GNOME Shell extensions, system tray
- **Security Settings**: Download verification, HTTPS enforcement

## 🎯 Optimization Features

### Wayland Native Support
- Dynamic backend detection (Wayland/X11)
- Ozone platform optimization
- Native input method integration
- Hardware-accelerated rendering

### Performance Enhancements  
- **GPU Acceleration**: VAAPI, Vulkan, hardware rasterization
- **Memory Optimization**: Zero-copy rendering, native GPU buffers
- **CPU Efficiency**: Multi-threaded operations, async processing
- **I/O Performance**: Parallel downloads, optimized file operations

### Desktop Integration
- Native system tray support
- GNOME Shell integration
- Proper window management
- Keyboard shortcut integration
- Notification system integration

## 🔄 Update Management

The installer includes intelligent update management:

```bash
# Check for updates
./install.sh check

# Update to latest version
./install.sh update

# Automatic update notifications
claude-desktop-installer --check-updates
```

## 🐛 Troubleshooting

### Common Issues

**Window not movable/draggable**
- Ensure you're running the latest version (3.0.0+)
- Check that Wayland optimizations are enabled
- Try forcing X11 mode: `export GDK_BACKEND=x11`

**Performance Issues**
- Verify hardware acceleration: `vainfo` and `vulkaninfo`
- Check GPU drivers are up to date
- Enable debug logging: `./install.sh --verbose`

**Installation Failures**
- Ensure all dependencies are installed
- Check system requirements
- Review logs: `/tmp/claude-installer.log`

### Debug Mode
```bash
# Enable verbose logging
export LOG_LEVEL=DEBUG
./install.sh install --verbose

# Generate system report
src/utils/system-detection.sh generate_system_report
```

## 🤝 Contributing

Contributions are welcome! Please see our contribution guidelines:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Setup
```bash
# Clone repository
git clone https://github.com/CaullenOmdahl/claude-desktop-fedora.git
cd claude-desktop-fedora

# Run tests
./scripts/test.sh

# Validate configuration
ajv validate -s config/schema.json -d config/default.json
```

## 📄 License

This project is dual-licensed under:
- [MIT License](LICENSE-MIT) 
- [Apache License 2.0](LICENSE-APACHE)

Choose the license that best suits your needs.

## 🙏 Acknowledgments

- **Anthropic** for creating Claude Desktop
- **Fedora Community** for the excellent Linux distribution  
- **Wayland/GNOME Teams** for the modern desktop stack
- **Contributors** who help improve this project

## 📞 Support

- 🐛 **Issues**: [GitHub Issues](https://github.com/CaullenOmdahl/claude-desktop-fedora/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/CaullenOmdahl/claude-desktop-fedora/discussions)
- 📧 **Contact**: [Caullen.Omdahl@gmail.com](mailto:Caullen.Omdahl@gmail.com)

---

<p align="center">
  <strong>⭐ Star this repo if it helped you! ⭐</strong><br>
  Made with ❤️ for the Fedora Linux community
</p>