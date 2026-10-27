# Universal macOS & Linux System Cleaner & Updater (Pro Ultimate)

![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![macOS](https://img.shields.io/badge/macOS-27%20Golden%20Gate%20%2F%20Bridge%20%7C%20Apple%20Silicon%20(M1--M4)-orange.svg)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github-sponsors)](https://github.com/sponsors/GabxSup)
![Linux](https://img.shields.io/badge/Linux-Ubuntu%20%7C%20Debian%20%7C%20Fedora%20%7C%20Arch%20%7C%20openSUSE-purple.svg)

An advanced, automated, enterprise-grade maintenance script for macOS and Linux. It performs deep-cleaning of developer environments, system caches, logs, containers, and stale virtual environments (`.envs`), while calculating and reporting the **exact amount of disk space reclaimed** in real time. Now featuring a dedicated **Security Clean & Privacy Audit** engine.

---

## What's New in v3.0 (Pro Ultimate)

### 1. Security Clean & Privacy Audit
- **Crash Dumps & Diagnostic Purge**: Clears unhandled core dumps (`/cores`, `/var/crash`, `coredumpctl`) and DiagnosticReports to prevent sensitive memory or token leakage.
- **Abandoned Auth Sockets**: Purges dead SSH and GPG agent sockets in `/tmp` and `/var/tmp` left by severed sessions.
- **Privacy & History Hygiene**: Sanitizes root and user CLI credential artifacts (`.lesshst`, `.wget-hsts`, `.viminfo`, `.mysql_history`, `.node_repl_history`, `.python_history`).
- **Quarantine Events Purge (macOS)**: Cleans the LaunchServices `QuarantineEvents` database containing records of all internet downloads and origins.
- **Permissions & Security Audit**: Strips world-writable permissions from critical `/etc` files, audits unowned files, and verifies Gatekeeper and SIP status on macOS.
- **Security Advisories (Linux)**: Scans and logs pending distro-specific security patches (APT, DNF, Zypper, Arch).
- **Credential Flush**: Automatically flushes cached `sudo` timestamp tokens upon completion.

### 2. macOS 27 ("Golden Gate / Golden Bridge") & Apple Silicon Optimized
- Full native support for **macOS 27 (Golden Gate / Bridge)**, **macOS 15 (Sequoia)**, and **macOS 14 (Sonoma)**.
- First-class support for **Apple Silicon (`arm64` - M1, M2, M3, M4)** and Intel (`x86_64`).
- Universal PATH injection: detects `/opt/homebrew` and `/usr/local` seamlessly across shells and subshells.
- **Smart Sudo Keepalive**: Requests administrator privileges once interactively at start and maintains a secure background keepalive session — preventing stalled prompts or terminal lockups during log redirection.
- Deep macOS maintenance: Inactive RAM purge (`purge`), System & User cache cleanup (`/Library/Caches` and `~/Library/Caches`), QuickLook thumbnail cache reset (`qlmanage -r cache`), DNS cache flush, Saved Application State cleanup, and Diagnostic/Crash reports cleanup.

### 3. Python Virtual Environments (`.envs`) Deep Cleaner & Auditor
- **Broken Virtual Environment Scanner**: Detects orphan or broken `.venv` / `venv` directories left behind after macOS or Python upgrades where the base Python symlink is missing or invalid.
- **Global Python Environment Caches**: Cleans `uv`, `pip`, `poetry`, `pipenv`, `pyenv`, `conda`, and `~/.virtualenvs`.
- **Absolute Safety**: Guarantees that **`.env` secret/configuration files are NEVER touched**; only virtual environment runtime directories are audited.

### 4. Comprehensive Developer Tools Deep Cleaning
- **Xcode & Apple Dev**: Prunes `DerivedData`, `Archives`, `iOS DeviceSupport` (can save 10GB–50GB), `CoreSimulator Caches`, and unavailable simulators (`xcrun simctl delete unavailable`).
- **Homebrew**: Runs `brew update`, `brew upgrade`, `brew autoremove` (removes orphan dependencies), and `brew cleanup -s --prune=all`.
- **Modern JavaScript/TypeScript**: Cleans `npm`, `yarn`, `pnpm store`, and `bun` package caches.
- **Rust / Go / Java / Mobile**: Cleans Cargo registry/git checkouts, Go build/module caches, Gradle caches, Android SDK build caches, CocoaPods caches, Flutter caches, and Composer.
- **Containers**: Prunes dangling Docker images, stopped containers, build caches, and unused volumes (`docker system prune -a --volumes` & `docker builder prune -a`).
- **AI / ML Caches**: Cleans temporary downloads and locks in Hugging Face (`~/.cache/huggingface/hub/tmp*`) and Torch cache.

### 5. Real-Time Disk Space Saved Tracking
- Automatically captures free disk space before and after execution.
- Measures individual cache sizes before removal using `du -sk`.
- Displays real-time reclaimed space in both the live progress bar and final summary report:
  ```text
  =====================================================
                 DISK SPACE SAVINGS REPORT            
  =====================================================
    Initial Free Space         : 24.64 GB
    Current Free Space         : 29.86 GB
    Net Disk Space Reclaimed   : +5.22 GB
    Tracked Cleaned Files      : 5.45 GB
  =====================================================
  ```

### 6. Modular CLI Modes & Dry-Run Simulation
- `--dry-run` (`-d`): Preview exactly how much disk space would be freed without deleting anything.
- `--dev-only`: Only clean developer toolchains, caches, and virtual environments.
- `--system-only`: Only clean OS-level caches, logs, temp files, trash, DNS, and memory.
- `--security`: Only run Security Clean and Privacy audit.
- `--scan-venvs [DIR]`: Scan custom project directories for broken virtual environments.
- `--no-update`: Skip package manager updates for ultra-fast cache cleaning.
- `--yes` (`-y`): Non-interactive mode for automated cron jobs or CI pipelines.

---

## Supported Operating Systems & Package Managers

| OS / Distribution | Architecture | Supported Package Managers & Tools |
| :--- | :--- | :--- |
| **macOS 27 (Golden Gate / Bridge)** | Apple Silicon (`arm64`), Intel (`x86_64`) | Homebrew, Mac App Store (`mas`), Xcode, Docker, uv, npm, pip |
| **macOS 15 (Sequoia) & 14 (Sonoma)**| Apple Silicon (`arm64`), Intel (`x86_64`) | Homebrew, Mac App Store (`mas`), Xcode, Docker, uv, npm, pip |
| **Ubuntu / Debian / Mint / Pop!_OS**| x86_64, aarch64 | `apt`, `snap`, `flatpak`, Docker |
| **Fedora / RHEL / CentOS / Rocky** | x86_64, aarch64 | `dnf`, `flatpak`, Docker |
| **Arch Linux / Manjaro / Endeavour**| x86_64, aarch64 | `pacman`, AUR wrappers, Docker |
| **openSUSE / SLES** | x86_64, aarch64 | `zypper`, Docker |

---

## Usage

### 1. Clone the repository
```bash
git clone https://github.com/GabxSup/Mac-Cleaner.git
cd Mac-Cleaner
```

### 2. Make executable
```bash
chmod +x cleaner.sh
```

### 3. Run the script

#### On macOS (Golden Gate / Bridge / Sequoia / Sonoma):
```bash
# Full maintenance (interactive - prompts for sudo once if system cleaning is desired)
./cleaner.sh

# Security & privacy audit only
./cleaner.sh --security

# Dry-run preview (see potential space savings without touching files)
./cleaner.sh --dry-run

# Developer-only clean (no sudo required)
./cleaner.sh --dev-only

# Scan for broken Python virtual environments in a project folder
./cleaner.sh --scan-venvs ~/Documents
```

#### On Linux:
```bash
sudo ./cleaner.sh
```

---

## CLI Options Reference

```text
Usage:
  ./cleaner.sh [OPTIONS]

Options:
  -h, --help           Show this help message and exit.
  -d, --dry-run        Simulate operations and estimate space saved without deleting anything.
  --dev, --dev-only    Only clean developer tools (Xcode, Homebrew, Docker, Node, Python, venvs, caches).
  --system, --sys-only Only clean OS caches, logs, temp files, trash, DNS, and memory.
  --security           Only run Security Clean & Privacy audit (crash dumps, stale sockets, credential artifacts).
  --scan-venvs [DIR]   Search for and clean broken/orphan Python virtual environments in DIR (default: home).
  --no-update          Skip package updates (brew/apt/dnf upgrade) and only perform cleaning tasks.
  -y, --yes            Automatic confirmation mode (non-interactive).
```

---

## Logging & Diagnostics

All execution logs and technical outputs are saved to:
- **macOS**: `~/Library/Logs/system_cleaner.log`
- **Linux**: `/var/log/system_cleaner.log`

This keeps your terminal clean while preserving complete records for troubleshooting.

---

## Safety & Integrity

- **Protected Secrets**: Never touches `.env`, `.env.local`, or any configuration files containing environment variables or credentials.
- **Safe Virtualenvs**: Only targets virtual environments whose base Python binary is broken or dead, and asks for confirmation prior to removal.
- **Graceful Privileges**: If run without administrator privileges on macOS, it safely skips root-only tasks (like system logs) and proceeds with 100% of user and developer cleaning tasks.
- **Credential Hygiene**: Automatically flushes any cached administrator/sudo timestamp credentials on exit.

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
