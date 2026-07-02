# Universal Linux & macOS System Cleaner & Updater

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg) ![License](https://img.shields.io/badge/license-MIT-green.svg)

An advanced, automated bash script to keep your Linux and macOS systems fresh, updated, and clean. Now featuring a **visual progress bar**, **detailed task summaries**, and extended support for modern container, package, and developer environments.

## 🚀 New Features (v2.0)

- **Interactive UI**: A sleek progress bar `[####....] 40%` keeps you informed of the current operation.
- **Task Summary**: Get a clear report at the end showing exactly which tasks succeeded ✔ and which failed ✘.
- **Extended Cleaning**:
  - **Docker**: Prunes unused containers, networks, and images (`docker system prune`).
  - **Snap & Flatpak**: Updates and cleans these package managers if detected.
  - **Systemd Journal / macOS Logs**: Vacuums old logs to save disk space.
  - **macOS Dev / Cache files**: Cleans Xcode DerivedData/Archives, User Caches, Trash, and flushes DNS cache.
- **Smart Detection**: Automatically detects your OS/distro and installed tools (Docker, Snap, Homebrew, etc.) to tailor the cleaning process.

## 📦 Supported Systems

The script automatically detects and adapts to the following package managers and systems:

- **macOS** (`Homebrew` & `mas`)
- **Debian / Ubuntu / Kali / Mint / Pop!_OS** (`apt`)
- **Fedora / RHEL / CentOS / AlmaLinux / Rocky** (`dnf`)
- **Arch Linux / Manjaro / EndeavourOS** (`pacman`)
- **OpenSUSE / SLES** (`zypper`)

## 🛠 Usage

1.  **Download** or clone this repository:
    ```bash
    git clone https://github.com/GabxSup/Linux-Cleaner.git
    cd Linux-Cleaner
    ```

2.  **Make executable**:
    ```bash
    chmod +x cleaner.sh
    ```

3.  **Run the script**:
    - **On Linux (Requires sudo)**:
      ```bash
      sudo ./cleaner.sh
      ```
    - **On macOS (Do NOT run with sudo directly)**:
      ```bash
      ./cleaner.sh
      ```
      *Note: On macOS, the script will request your password dynamically for tasks that require sudo (like cleaning system logs or flushing DNS).*

## 📝 Logging

All technical details and command outputs are logged to:
- **Linux**: `/var/log/system_cleaner.log`
- **macOS**: `~/Library/Logs/system_cleaner.log`

This keeps your terminal clean while preserving all data for troubleshooting.

## ⚠️ Disclaimer

This script performs system administration tasks (updates, upgrades, cache cleaning). While tested and intended to be safe, **always review scripts before running them**. Use at your own risk.

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.
