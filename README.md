# bpm - Binary Package Manager

**Version:** 0.3.0

A lightweight, POSIX-compliant package manager for managing binary packages, dependencies, and tools on Unix-like systems.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [Configuration](#configuration)
- [Package Management](#package-management)
- [Hooks System](#hooks-system)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🔍 Overview

bpm is a binary package manager designed for simplicity and flexibility. It provides a robust framework for installing, updating, and managing binary packages with features like dependency resolution, transaction safety, and plugin support.

## ✨ Features

- **Package Management**: Install, remove, update, and list packages
- **Dependency Resolution**: Automatic dependency tracking and conflict resolution
- **Transaction System**: Atomic operations with rollback support
- **Plugin Architecture**: Extensible via custom plugins
- **Hook System**: Execute custom scripts at various lifecycle events
- **Multi-Repository Support**: Manage packages from multiple sources
- **Lock System**: Prevents concurrent operations
- **Progress Tracking**: Visual feedback for long-running operations
- **Color Support**: Enhanced terminal output with tput
- **Logging**: Comprehensive logging for debugging and auditing

## 📦 Installation

### Quick Install

```bash
# Download and install bpm
curl -fsSL https://raw.githubusercontent.com/zhexhem/bpm/main/install.sh | bash

# Or with wget
wget -qO- https://raw.githubusercontent.com/zhexhem/bpm/main/install.sh | bash