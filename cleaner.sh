#!/bin/bash

# ==============================================================================
# Script Name: Universal macOS & Linux System Cleaner & Updater (Pro Ultimate)
# Description: Automated, deep-cleaning & update tool optimized for macOS
#              (including macOS 27 Golden Gate / Golden Bridge, Apple Silicon arm64)
#              and major Linux distributions. Tracks disk space reclaimed in real-time.
# Author: GabxSup - https://github.com/GabxSup
# License: MIT
# Version: 3.0.0
# ==============================================================================

# Ensure common paths are in PATH (critical on macOS Apple Silicon & modern dev setups)
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- Configuration & Logging ---
if [[ "$(uname -s)" == "Darwin" ]]; then
    LOG_FILE="$HOME/Library/Logs/system_cleaner.log"
else
    LOG_FILE="/var/log/system_cleaner.log"
fi
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Resolve invoking user home and execution prefix when elevated with sudo
USER_HOME="$HOME"
RUN_USER=""
if [[ -n "$SUDO_USER" ]]; then
    RUN_USER="sudo -u $SUDO_USER"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        USER_HOME=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    else
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    fi
    [[ -z "$USER_HOME" ]] && USER_HOME="$HOME"
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Global Variables & Flags ---
TOTAL_STEPS=0
CURRENT_STEP=0
SUMMARY_LOG=()
ERRORS_LOG=()
UPDATES_AVAILABLE=false

# CLI Flags
DRY_RUN=false
MODE="all" # "all", "dev", "system"
SKIP_UPDATES=false
AUTO_YES=false
SCAN_VENV_PATH=""
HAS_SUDO=false
SUDO_PID=""

# Disk Space Tracking (in KB)
INITIAL_FREE_KB=0
FINAL_FREE_KB=0
TOTAL_FREED_KB=0

# Auto-cleanup temp file and sudo keepalive on exit
UPDATES_LIST_FILE=$(mktemp)
cleanup_on_exit() {
    rm -f "$UPDATES_LIST_FILE"
    if [[ -n "$SUDO_PID" ]]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
}
trap cleanup_on_exit EXIT

# Ensure log file is writable (fixes permissions if root created it in user directory)
ensure_logfile_writable() {
    if [[ -f "$LOG_FILE" && ! -w "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null
    fi
    if [[ ! -w "$LOG_FILE" && ! -w "$(dirname "$LOG_FILE" 2>/dev/null)" ]]; then
        LOG_FILE="/tmp/system_cleaner_${USER:-user}.log"
    fi
    touch "$LOG_FILE" 2>/dev/null || true
}
ensure_logfile_writable

# --- Helper Functions ---

log() {
    echo "[$DATE] [INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo "[$DATE] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo "[$DATE] [ERROR] $1" >> "$LOG_FILE"
}

# Format KB into human-readable representation (KB, MB, GB, TB)
format_kb() {
    local kb="$1"
    if [[ -z "$kb" || "$kb" -le 0 ]]; then
        echo "0 B"
        return
    fi
    awk -v kb="$kb" 'BEGIN {
        if (kb < 1024) {
            printf "%d KB", kb
        } else if (kb < 1048576) {
            printf "%.2f MB", kb / 1024
        } else if (kb < 1073741824) {
            printf "%.2f GB", kb / 1048576
        } else {
            printf "%.2f TB", kb / 1073741824
        }
    }'
}

# Get free space in KB for the filesystem containing target path
get_free_disk_kb() {
    local target="${1:-$USER_HOME}"
    df -k "$target" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Measure size of path in KB
measure_path_kb() {
    local target="$1"
    if [[ ! -e "$target" ]]; then
        echo 0
        return
    fi
    local size
    size=$(du -sk "$target" 2>/dev/null | awk '{print $1}')
    if [[ -z "$size" || ! "$size" =~ ^[0-9]+$ ]]; then
        echo 0
    else
        echo "$size"
    fi
}

detect_distro() {
    OS_TYPE=$(uname -s)
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        DISTRO="macos"
        MACOS_VER=$(sw_vers -productVersion 2>/dev/null || echo "")
        ARCH=$(uname -m)
        case "$MACOS_VER" in
            27.*) MACOS_NICK="macOS 27 (Golden Gate / Bridge)" ;;
            15.*) MACOS_NICK="macOS 15 (Sequoia)" ;;
            14.*) MACOS_NICK="macOS 14 (Sonoma)" ;;
            13.*) MACOS_NICK="macOS 13 (Ventura)" ;;
            12.*) MACOS_NICK="macOS 12 (Monterey)" ;;
            *) MACOS_NICK="macOS $MACOS_VER" ;;
        esac
        OS_DISPLAY_INFO="$MACOS_NICK ($ARCH)"
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            OS_DISPLAY_INFO="${NAME:-Linux} ($(uname -m))"
        else
            echo -e "${RED}[ERROR] Cannot detect Linux distribution.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR] Unsupported Operating System: $OS_TYPE${NC}"
        exit 1
    fi
    log "Detected OS: $OS_DISPLAY_INFO (Distro identifier: $DISTRO)"
}

setup_privileges() {
    if [[ "$DISTRO" == "macos" ]]; then
        if [[ $EUID -eq 0 ]]; then
            HAS_SUDO=true
            log "Running as root on macOS. Dropping privileges to $SUDO_USER for user tasks."
        elif [[ "$MODE" == "dev" || "$DRY_RUN" == true ]]; then
            HAS_SUDO=false
        else
            # Request sudo once interactively if needed
            echo -e "${CYAN}[macOS] Checking administrator privileges for system-level cleaning...${NC}"
            if sudo -v 2>/dev/null; then
                HAS_SUDO=true
                # Keep-alive in background
                ( while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done ) 2>/dev/null &
                SUDO_PID=$!
                log "Sudo keep-alive initialized (PID: $SUDO_PID)"
            else
                echo -e "${YELLOW}[NOTE] Sudo privileges not granted. System-level cleaning tasks will be skipped.${NC}"
                HAS_SUDO=false
            fi
        fi
    else
        # Linux requires root for full system update/cleanup
        if [[ $EUID -ne 0 && "$DRY_RUN" != true ]]; then
            echo -e "${RED}[ERROR] This script must be run as root on Linux.${NC}"
            echo "Please run: sudo ./cleaner.sh"
            log_error "Script run without root privileges on Linux."
            exit 1
        fi
        HAS_SUDO=true
    fi
}

# --- CLI Argument Parsing & Help ---

show_help() {
    cat << EOF
Universal macOS & Linux System Cleaner & Updater (Pro Ultimate v3.0.0)

Usage:
  ./cleaner.sh [OPTIONS]

Options:
  -h, --help           Show this help message and exit.
  -d, --dry-run        Simulate operations and estimate space saved without deleting anything.
  --dev, --dev-only    Only clean developer tools (Xcode, Homebrew, Docker, Node, Python, venvs, caches).
  --system, --sys-only Only clean OS caches, logs, temp files, trash, DNS, and memory.
  --scan-venvs [DIR]   Search for and clean broken/orphan Python virtual environments in DIR (default: home).
  --no-update          Skip package updates (brew/apt/dnf upgrade) and only perform cleaning tasks.
  -y, --yes            Automatic confirmation mode (non-interactive).

Supported Platforms:
  - macOS 27+ (Golden Gate / Bridge), Sonoma, Sequoia - Apple Silicon (arm64) & Intel
  - Linux (Ubuntu, Debian, Fedora, Arch, openSUSE, etc.)

Examples:
  ./cleaner.sh                 # Full system & dev maintenance with live space tracking
  ./cleaner.sh --dry-run       # Check how much space would be saved without deleting anything
  ./cleaner.sh --dev-only      # Quick cleanup of dev caches (Node, Python, Xcode, Docker)
  ./cleaner.sh --scan-venvs    # Find broken Python virtual environments (.env secrets are never touched)

Logs are written to:
  macOS: ~/Library/Logs/system_cleaner.log
  Linux: /var/log/system_cleaner.log
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --dev|--dev-only)
                MODE="dev"
                shift
                ;;
            --system|--system-only|--sys-only)
                MODE="system"
                shift
                ;;
            --no-update)
                SKIP_UPDATES=true
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --scan-venvs)
                if [[ -n "$2" && "$2" != -* ]]; then
                    SCAN_VENV_PATH="$2"
                    shift 2
                else
                    SCAN_VENV_PATH="$USER_HOME"
                    shift
                fi
                ;;
            *)
                echo -e "${RED}[ERROR] Unknown option: $1${NC}"
                echo "Use --help to view available options."
                exit 1
                ;;
        esac
    done
}

# --- UI & Progress Bar ---

draw_progress_bar() {
    local description="$1"
    local width=38
    local percent=0
    if [ $TOTAL_STEPS -gt 0 ]; then
        percent=$(( 100 * CURRENT_STEP / TOTAL_STEPS ))
    fi
    if [ $percent -gt 100 ]; then percent=100; fi
    
    local filled=$(( width * percent / 100 ))
    local empty=$(( width - filled ))
    
    printf "\r"
    printf "${BLUE}[${NC}"
    
    local filled_chars=""
    for ((i=0; i<filled; i++)); do filled_chars="${filled_chars}#"; done
    printf "${GREEN}%s${NC}" "$filled_chars"
    
    local empty_chars=""
    for ((i=0; i<empty; i++)); do empty_chars="${empty_chars}."; done
    printf "%s" "$empty_chars"
    
    printf "${BLUE}]${NC} ${percent}%% - ${CYAN}%-42s${NC}" "$description"
    printf "\033[K"
}

# Run a path cleanup task (measures size, deletes contents or directory, tracks freed space)
run_clean_path() {
    local description="$1"
    local clean_mode="$2"   # "contents" (delete files inside) or "dir" (delete directory itself)
    local target_paths="$3" # Space-separated paths
    local custom_rm_cmd="$4"

    ((CURRENT_STEP++))
    draw_progress_bar "$description..."
    log "STARTING CLEAN: $description"

    local freed_kb=0
    for p in $target_paths; do
        if [[ -e "$p" ]]; then
            local sz
            sz=$(measure_path_kb "$p")
            ((freed_kb += sz))
        fi
    done

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: $description would reclaim $(format_kb $freed_kb)"
        if [[ $freed_kb -gt 0 ]]; then
            SUMMARY_LOG+=("${GREEN}✔${NC} [DRY-RUN] $description (Would reclaim: ${CYAN}$(format_kb $freed_kb)${NC})")
            ((TOTAL_FREED_KB += freed_kb))
        else
            SUMMARY_LOG+=("${GREEN}✔${NC} [DRY-RUN] $description (Already clean)")
        fi
        return 0
    fi

    local success=true
    if [[ -n "$custom_rm_cmd" ]]; then
        if ! eval "$custom_rm_cmd" >> "$LOG_FILE" 2>&1; then
            success=false
        fi
    else
        for p in $target_paths; do
            if [[ "$clean_mode" == "contents" && -d "$p" ]]; then
                find "$p" -mindepth 1 -delete 2>> "$LOG_FILE" || rm -rf "${p:?}"/* 2>> "$LOG_FILE" || true
            elif [[ "$clean_mode" == "dir" && -e "$p" ]]; then
                rm -rf "${p:?}" 2>> "$LOG_FILE" || true
            fi
        done
    fi

    if [[ "$success" == true ]]; then
        ((TOTAL_FREED_KB += freed_kb))
        log "COMPLETED: $description (Freed: $(format_kb $freed_kb))"
        if [[ $freed_kb -gt 0 ]]; then
            SUMMARY_LOG+=("${GREEN}✔${NC} $description (Freed: ${CYAN}$(format_kb $freed_kb)${NC})")
        else
            SUMMARY_LOG+=("${GREEN}✔${NC} $description (Already clean)")
        fi
    else
        log_error "FAILED: $description"
        SUMMARY_LOG+=("${RED}✘${NC} $description")
        ERRORS_LOG+=("$description")
    fi
}

# Run a command task with optional disk delta tracking
run_cmd_task() {
    local description="$1"
    local command="$2"
    local track_disk_delta="${3:-false}"

    ((CURRENT_STEP++))
    draw_progress_bar "$description..."
    log "STARTING: $description"

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Skipping execution of '$command'"
        SUMMARY_LOG+=("${GREEN}✔${NC} [DRY-RUN] $description")
        return 0
    fi

    local pre_free=0
    if [[ "$track_disk_delta" == true ]]; then
        pre_free=$(get_free_disk_kb)
    fi

    if eval "$command" >> "$LOG_FILE" 2>&1; then
        local delta_msg=""
        if [[ "$track_disk_delta" == true ]]; then
            local post_free
            post_free=$(get_free_disk_kb)
            if [[ $post_free -gt $pre_free ]]; then
                local delta=$((post_free - pre_free))
                ((TOTAL_FREED_KB += delta))
                delta_msg=" (Freed: ${CYAN}$(format_kb $delta)${NC})"
            fi
        fi
        log "COMPLETED: $description"
        SUMMARY_LOG+=("${GREEN}✔${NC} $description$delta_msg")
    else
        log_error "FAILED: $description"
        SUMMARY_LOG+=("${RED}✘${NC} $description")
        ERRORS_LOG+=("$description")
    fi
}

# --- Package Updates Capture ---

capture_updates_apt() {
    log "Checking for available APT updates..."
    if apt list --upgradable 2>/dev/null | grep -v "Listing..." > "$UPDATES_LIST_FILE"; then
        [ -s "$UPDATES_LIST_FILE" ] && UPDATES_AVAILABLE=true
    fi
}

capture_updates_dnf() {
    log "Checking for available DNF updates..."
    if dnf list upgrades -q > "$UPDATES_LIST_FILE" 2>/dev/null; then
        [ -s "$UPDATES_LIST_FILE" ] && UPDATES_AVAILABLE=true
    fi
}

capture_updates_pacman() {
    log "Checking for available Pacman updates..."
    if pacman -Qu > "$UPDATES_LIST_FILE" 2>/dev/null; then
        [ -s "$UPDATES_LIST_FILE" ] && UPDATES_AVAILABLE=true
    fi
}

capture_updates_zypper() {
    log "Checking for available Zypper updates..."
    if zypper list-updates > "$UPDATES_LIST_FILE" 2>/dev/null; then
        [ -s "$UPDATES_LIST_FILE" ] && UPDATES_AVAILABLE=true
    fi
}

# --- Calculation of Steps ---

calculate_total_steps() {
    TOTAL_STEPS=0

    # macOS System Tasks
    if [[ "$DISTRO" == "macos" && "$MODE" != "dev" ]]; then
        ((TOTAL_STEPS+=5)) # User Caches, Logs, AppState, Trash, QuickLook
        if [[ "$HAS_SUDO" == true ]]; then
            ((TOTAL_STEPS+=4)) # System Logs, Temp, DNS flush, Memory purge
        fi
    fi

    # Linux System Tasks
    if [[ "$DISTRO" != "macos" && "$MODE" != "dev" ]]; then
        ((TOTAL_STEPS+=3)) # Temp, Old logs, Thumbnails/Trash
        command -v journalctl >/dev/null 2>&1 && ((TOTAL_STEPS++))
    fi

    # Package Manager Updates/Cleans
    if [[ "$MODE" != "system" ]]; then
        if [[ "$DISTRO" == "macos" ]]; then
            if command -v brew >/dev/null 2>&1; then
                if [[ "$SKIP_UPDATES" != true ]]; then
                    ((TOTAL_STEPS+=2)) # update, upgrade
                fi
                ((TOTAL_STEPS+=2)) # autoremove, cleanup
            fi
            if command -v mas >/dev/null 2>&1 && [[ "$SKIP_UPDATES" != true ]]; then
                ((TOTAL_STEPS++))
            fi
        else
            # Linux package managers
            case "$DISTRO" in
                ubuntu|debian|kali|linuxmint|pop)
                    [[ "$SKIP_UPDATES" != true ]] && ((TOTAL_STEPS+=3))
                    ((TOTAL_STEPS+=2)) # autoclean, autoremove
                    ;;
                fedora|rhel|centos|almalinux|rocky)
                    [[ "$SKIP_UPDATES" != true ]] && ((TOTAL_STEPS+=3))
                    ((TOTAL_STEPS+=2)) # clean, autoremove
                    ;;
                arch|manjaro|endeavouros)
                    [[ "$SKIP_UPDATES" != true ]] && ((TOTAL_STEPS+=1))
                    ((TOTAL_STEPS+=4))
                    ;;
                opensuse*|sles)
                    [[ "$SKIP_UPDATES" != true ]] && ((TOTAL_STEPS+=3))
                    ((TOTAL_STEPS+=2))
                    ;;
            esac
            command -v snap >/dev/null 2>&1 && [[ "$SKIP_UPDATES" != true ]] && ((TOTAL_STEPS++))
            command -v flatpak >/dev/null 2>&1 && ((TOTAL_STEPS+=2))
        fi

        # Developer Tools & Environments
        # Xcode & Simulators
        if [[ "$DISTRO" == "macos" ]]; then
            [ -d "$USER_HOME/Library/Developer/Xcode" ] && ((TOTAL_STEPS+=3)) # DerivedData, Archives, iOS DeviceSupport
            [ -d "$USER_HOME/Library/Developer/CoreSimulator/Caches" ] && ((TOTAL_STEPS++))
            if xcrun simctl list devices >/dev/null 2>&1; then
                ((TOTAL_STEPS++)) # simctl delete unavailable
            fi
            command -v pod >/dev/null 2>&1 || [ -d "$USER_HOME/Library/Caches/CocoaPods" ] && ((TOTAL_STEPS++))
        fi

        # Node / JS
        command -v npm >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v yarn >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v pnpm >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v bun >/dev/null 2>&1 && ((TOTAL_STEPS++))

        # Python & Environments
        command -v uv >/dev/null 2>&1 || [ -d "$USER_HOME/.cache/uv" ] && ((TOTAL_STEPS++))
        command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v poetry >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v pipenv >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v conda >/dev/null 2>&1 && ((TOTAL_STEPS++))
        # Global virtualenvs / pyenv
        if [ -d "$USER_HOME/.virtualenvs" ] || [ -d "$USER_HOME/.pyenv/cache" ]; then
            ((TOTAL_STEPS++))
        fi
        # Broken virtual environment scan
        ((TOTAL_STEPS++))

        # Rust / Go / Java / Other
        command -v cargo >/dev/null 2>&1 || [ -d "$USER_HOME/.cargo/registry/cache" ] && ((TOTAL_STEPS++))
        command -v go >/dev/null 2>&1 && ((TOTAL_STEPS++))
        [ -d "$USER_HOME/.gradle/caches" ] && ((TOTAL_STEPS++))
        [ -d "$USER_HOME/.android/cache" ] || [ -d "$USER_HOME/.android/build-cache" ] && ((TOTAL_STEPS++))
        command -v composer >/dev/null 2>&1 && ((TOTAL_STEPS++))
        command -v flutter >/dev/null 2>&1 && ((TOTAL_STEPS++))

        # Docker / Podman
        if command -v docker >/dev/null 2>&1; then
            if docker system info >/dev/null 2>&1; then
                ((TOTAL_STEPS+=2))
            fi
        fi
        command -v podman >/dev/null 2>&1 && ((TOTAL_STEPS++))

        # AI / ML Caches
        if [ -d "$USER_HOME/.cache/huggingface" ] || [ -d "$USER_HOME/.cache/torch" ]; then
            ((TOTAL_STEPS++))
        fi
    fi
}

# --- Broken Virtual Environments (.envs) Scanner & Cleaner ---

task_scan_broken_venvs() {
    ((CURRENT_STEP++))
    draw_progress_bar "Scanning broken virtual environments..."
    log "Scanning for broken Python virtual environments..."

    local broken_venvs=()
    local broken_sizes=()
    local total_broken_sz=0

    local search_roots=()
    if [[ -n "$SCAN_VENV_PATH" ]]; then
        search_roots=("$SCAN_VENV_PATH")
    else
        for dir in "$USER_HOME/Documents" "$USER_HOME/Projects" "$USER_HOME/Developer" "$USER_HOME/workspace" "$USER_HOME/src" "$PWD"; do
            if [[ -d "$dir" ]]; then
                search_roots+=("$dir")
            fi
        done
        [[ ${#search_roots[@]} -eq 0 ]] && search_roots=("$USER_HOME")
    fi

    # Scan for pyvenv.cfg (excluding Library, Trash, node_modules)
    for root in "${search_roots[@]}"; do
        while IFS= read -r cfg_file; do
            local venv_dir
            venv_dir=$(dirname "$cfg_file")
            
            local is_broken=false
            if [[ -L "$venv_dir/bin/python" && ! -e "$venv_dir/bin/python" ]]; then
                is_broken=true
            elif [[ -L "$venv_dir/bin/python3" && ! -e "$venv_dir/bin/python3" ]]; then
                is_broken=true
            elif [[ ! -x "$venv_dir/bin/python" && ! -x "$venv_dir/bin/python3" ]]; then
                is_broken=true
            fi

            if [[ "$is_broken" == true ]]; then
                local already_found=false
                for existing in "${broken_venvs[@]}"; do
                    if [[ "$existing" == "$venv_dir" ]]; then
                        already_found=true
                        break
                    fi
                done
                if [[ "$already_found" == false ]]; then
                    local sz
                    sz=$(measure_path_kb "$venv_dir")
                    broken_venvs+=("$venv_dir")
                    broken_sizes+=("$sz")
                    ((total_broken_sz += sz))
                fi
            fi
        done < <(find "$root" -maxdepth 5 \( -path "*/Library" -o -path "*/.Trash" -o -path "*/node_modules" \) -prune -o -name "pyvenv.cfg" -print 2>/dev/null)
    done

    if [[ ${#broken_venvs[@]} -eq 0 ]]; then
        log "No broken Python virtual environments found."
        SUMMARY_LOG+=("${GREEN}✔${NC} Python virtual environments (.envs): All checked environments are healthy")
        return 0
    fi

    echo ""
    echo -e "\n${YELLOW}[!] Found ${#broken_venvs[@]} broken Python virtual environment(s) (Total: $(format_kb $total_broken_sz)):${NC}"
    for i in "${!broken_venvs[@]}"; do
        echo -e "    - ${CYAN}${broken_venvs[$i]}${NC} (${YELLOW}$(format_kb ${broken_sizes[$i]})${NC})"
    done
    echo -e "${BLUE}    (Note: .env secret configuration files are NEVER touched, only broken venv folders)${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        SUMMARY_LOG+=("${GREEN}✔${NC} [DRY-RUN] Broken virtual environments (Would free: ${CYAN}$(format_kb $total_broken_sz)${NC})")
        ((TOTAL_FREED_KB += total_broken_sz))
        return 0
    fi

    local should_delete=false
    if [[ "$AUTO_YES" == true ]]; then
        should_delete=true
    else
        read -p "Do you want to delete these broken virtual environments? [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            should_delete=true
        fi
    fi

    if [[ "$should_delete" == true ]]; then
        local deleted_count=0
        for dir in "${broken_venvs[@]}"; do
            if rm -rf "$dir" 2>> "$LOG_FILE"; then
                ((deleted_count++))
                log "Deleted broken virtual environment: $dir"
            fi
        done
        ((TOTAL_FREED_KB += total_broken_sz))
        SUMMARY_LOG+=("${GREEN}✔${NC} Removed $deleted_count broken virtual environment(s) (Freed: ${CYAN}$(format_kb $total_broken_sz)${NC})")
    else
        SUMMARY_LOG+=("${YELLOW}⚠${NC} Skipped removal of ${#broken_venvs[@]} broken virtual environment(s)")
    fi
}

# --- macOS Specific Tasks ---

task_macos() {
    # 1. System & User Cleaning
    if [[ "$MODE" != "dev" ]]; then
        run_clean_path "Cleaning User Caches (~/Library/Caches)" "contents" "$USER_HOME/Library/Caches"
        run_clean_path "Cleaning User Logs (~/Library/Logs)" "contents" "$USER_HOME/Library/Logs"
        run_clean_path "Cleaning Saved Application State" "contents" "$USER_HOME/Library/Saved Application State"
        run_clean_path "Emptying Trash (~/.Trash)" "contents" "$USER_HOME/.Trash"
        run_cmd_task "Resetting QuickLook Cache" "qlmanage -r cache"

        if [[ "$HAS_SUDO" == true ]]; then
            run_clean_path "Cleaning System Logs (/Library/Logs & /var/log)" "contents" "/Library/Logs /var/log/asl" "sudo rm -rf /Library/Logs/* /var/log/*.log /var/log/asl/* 2>/dev/null || true"
            run_clean_path "Cleaning System Temp files (/tmp & /var/tmp)" "contents" "/tmp /var/tmp" "sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true"
            run_cmd_task "Flushing macOS DNS Cache" "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
            run_cmd_task "Purging Inactive Memory" "sudo purge"
        fi
    fi

    # 2. Package Managers (Brew, MAS)
    if [[ "$MODE" != "system" ]]; then
        if command -v brew >/dev/null 2>&1; then
            if [[ "$SKIP_UPDATES" != true ]]; then
                run_cmd_task "Updating Homebrew formulae" "$RUN_USER brew update"
                run_cmd_task "Upgrading Homebrew packages" "$RUN_USER brew upgrade"
            fi
            run_cmd_task "Removing unused Homebrew dependencies" "$RUN_USER brew autoremove" true
            run_clean_path "Cleaning Homebrew cache & old versions" "contents" "$USER_HOME/Library/Caches/Homebrew" "$RUN_USER brew cleanup -s --prune=all"
        fi

        if command -v mas >/dev/null 2>&1 && [[ "$SKIP_UPDATES" != true ]]; then
            run_cmd_task "Upgrading Mac App Store apps" "$RUN_USER mas upgrade"
        fi

        # 3. Xcode & Apple Developer Tools
        if [ -d "$USER_HOME/Library/Developer/Xcode" ]; then
            run_clean_path "Cleaning Xcode DerivedData" "contents" "$USER_HOME/Library/Developer/Xcode/DerivedData"
            run_clean_path "Cleaning Xcode Archives" "contents" "$USER_HOME/Library/Developer/Xcode/Archives"
            run_clean_path "Cleaning Xcode iOS DeviceSupport" "contents" "$USER_HOME/Library/Developer/Xcode/iOS DeviceSupport"
        fi

        if [ -d "$USER_HOME/Library/Developer/CoreSimulator/Caches" ]; then
            run_clean_path "Cleaning CoreSimulator Caches" "contents" "$USER_HOME/Library/Developer/CoreSimulator/Caches"
        fi

        if xcrun simctl list devices >/dev/null 2>&1; then
            run_cmd_task "Pruning unavailable iOS Simulators" "$RUN_USER xcrun simctl delete unavailable" true
        fi

        if command -v pod >/dev/null 2>&1 || [ -d "$USER_HOME/Library/Caches/CocoaPods" ]; then
            run_clean_path "Cleaning CocoaPods cache" "contents" "$USER_HOME/Library/Caches/CocoaPods" "$RUN_USER pod cache clean --all 2>/dev/null || rm -rf \"$USER_HOME/Library/Caches/CocoaPods\"/* 2>/dev/null || true"
        fi
    fi
}

# --- Linux Package Managers ---

task_apt() {
    if [[ "$SKIP_UPDATES" != true ]]; then
        capture_updates_apt
        run_cmd_task "Updating APT repositories" "apt-get update -y"
        run_cmd_task "Upgrading packages" "apt-get upgrade -y"
        run_cmd_task "Distribution upgrade" "apt-get dist-upgrade -y"
    fi
    run_cmd_task "Cleaning APT cache" "apt-get autoclean -y" true
    run_cmd_task "Removing unused dependencies" "apt-get autoremove --purge -y" true
}

task_dnf() {
    if [[ "$SKIP_UPDATES" != true ]]; then
        capture_updates_dnf
        run_cmd_task "Refreshing DNF metadata" "dnf check-update || true"
        run_cmd_task "Upgrading system (DNF)" "dnf upgrade --refresh -y"
        run_cmd_task "System optimization (DNF)" "dnf distro-sync -y"
    fi
    run_cmd_task "Cleaning DNF cache" "dnf clean all" true
    run_cmd_task "Removing unused packages" "dnf autoremove -y" true
}

task_pacman() {
    if [[ "$SKIP_UPDATES" != true ]]; then
        capture_updates_pacman
        run_cmd_task "Syncing & Upgrading (Pacman)" "pacman -Syu --noconfirm"
    fi
    run_cmd_task "Checking database integrity" "pacman -Dk"
    run_cmd_task "Refreshing keyring" "pacman -Sy archlinux-keyring --noconfirm"
    run_cmd_task "Cleaning package cache" "pacman -Sc --noconfirm" true
    run_cmd_task "Removing orphans" "pacman -Rns \$(pacman -Qdtq) --noconfirm || true" true
}

task_zypper() {
    if [[ "$SKIP_UPDATES" != true ]]; then
        capture_updates_zypper
        run_cmd_task "Refreshing repositories" "zypper refresh"
        run_cmd_task "Upgrading packages" "zypper update -y"
        run_cmd_task "Distribution upgrade" "zypper dist-upgrade -y"
    fi
    run_cmd_task "Cleaning cache" "zypper clean --all" true
    run_cmd_task "Verifying dependencies" "zypper verify"
}

# --- Linux System Cleaning ---

task_linux_system_clean() {
    if command -v journalctl >/dev/null 2>&1; then
        run_cmd_task "Vacuuming systemd journals (keep 2 weeks)" "journalctl --vacuum-time=2weeks" true
    fi

    run_clean_path "Cleaning temporary files (/var/tmp)" "contents" "/var/tmp"

    run_cmd_task "Cleaning old compressed logs" "find /var/log -type f \( -name '*.gz' -o -name '*.1' \) -delete"

    # Deep clean thumbnails and trash
    shopt -s nullglob
    local user_caches=()
    for u_home in /home/* /root; do
        if [ -d "$u_home" ]; then
            [ -d "$u_home/.cache/thumbnails" ] && user_caches+=("$u_home/.cache/thumbnails")
            [ -d "$u_home/.local/share/Trash" ] && user_caches+=("$u_home/.local/share/Trash")
        fi
    done
    shopt -u nullglob
    if [ ${#user_caches[@]} -gt 0 ]; then
        run_clean_path "Cleaning User Thumbnails & Trash" "contents" "${user_caches[*]}"
    fi
}

# --- Cross-Platform Developer Tools & Environments ---

run_dev_tools_cleanup() {
    # 1. Snap & Flatpak (Linux)
    if [[ "$DISTRO" != "macos" ]]; then
        if command -v snap >/dev/null 2>&1 && [[ "$SKIP_UPDATES" != true ]]; then
            run_cmd_task "Refreshing Snap packages" "snap refresh"
        fi
        if command -v flatpak >/dev/null 2>&1; then
            if [[ "$SKIP_UPDATES" != true ]]; then
                run_cmd_task "Updating Flatpak packages" "flatpak update -y"
            fi
            run_cmd_task "Removing unused Flatpak runtimes" "flatpak uninstall --unused -y" true
        fi
    fi

    # 2. Node.js & JavaScript package managers
    if command -v npm >/dev/null 2>&1; then
        run_clean_path "Cleaning NPM cache" "contents" "$USER_HOME/.npm" "$RUN_USER npm cache clean --force"
    fi
    if command -v yarn >/dev/null 2>&1; then
        local yarn_cache="$USER_HOME/.cache/yarn"
        [[ "$DISTRO" == "macos" ]] && yarn_cache="$USER_HOME/Library/Caches/Yarn"
        run_clean_path "Cleaning Yarn cache" "contents" "$yarn_cache" "$RUN_USER yarn cache clean"
    fi
    if command -v pnpm >/dev/null 2>&1; then
        run_cmd_task "Pruning PNPM store" "$RUN_USER pnpm store prune" true
    fi
    if command -v bun >/dev/null 2>&1; then
        run_clean_path "Cleaning Bun cache" "contents" "$USER_HOME/.bun/install/cache" "$RUN_USER bun pm cache rm"
    fi

    # 3. Python Ecosystem & Environments
    if command -v uv >/dev/null 2>&1 || [ -d "$USER_HOME/.cache/uv" ]; then
        run_clean_path "Cleaning UV cache" "contents" "$USER_HOME/.cache/uv" "$RUN_USER uv cache clean 2>/dev/null || true"
    fi
    if command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
        local pip_cmd="pip3"
        command -v pip3 >/dev/null 2>&1 || pip_cmd="pip"
        local pip_cache="$USER_HOME/.cache/pip"
        [[ "$DISTRO" == "macos" ]] && pip_cache="$USER_HOME/Library/Caches/pip"
        run_clean_path "Cleaning PIP cache" "contents" "$pip_cache" "$RUN_USER $pip_cmd cache purge"
    fi
    if command -v poetry >/dev/null 2>&1; then
        run_clean_path "Cleaning Poetry cache" "contents" "$USER_HOME/.cache/pypoetry/cache" "$RUN_USER poetry cache clear --all . -n 2>/dev/null || true"
    fi
    if command -v pipenv >/dev/null 2>&1; then
        run_cmd_task "Clearing Pipenv cache" "$RUN_USER pipenv --clear"
    fi
    if command -v conda >/dev/null 2>&1; then
        run_cmd_task "Cleaning Conda packages & caches" "$RUN_USER conda clean --all -y" true
    fi
    if [ -d "$USER_HOME/.virtualenvs" ] || [ -d "$USER_HOME/.pyenv/cache" ]; then
        run_clean_path "Cleaning Pyenv & legacy virtualenv caches" "contents" "$USER_HOME/.pyenv/cache"
    fi

    # Scan & Clean broken project virtualenvs (.envs)
    task_scan_broken_venvs

    # 4. Rust / Cargo
    if command -v cargo >/dev/null 2>&1 || [ -d "$USER_HOME/.cargo/registry/cache" ]; then
        run_clean_path "Cleaning Cargo registry & git cache" "contents" "$USER_HOME/.cargo/registry/cache $USER_HOME/.cargo/git/checkouts"
    fi

    # 5. Go
    if command -v go >/dev/null 2>&1; then
        run_cmd_task "Cleaning Go build, test & module cache" "$RUN_USER go clean -cache -testcache -modcache" true
    fi

    # 6. Java / Gradle / Android
    if [ -d "$USER_HOME/.gradle/caches" ]; then
        run_clean_path "Cleaning Gradle caches" "contents" "$USER_HOME/.gradle/caches"
    fi
    if [ -d "$USER_HOME/.android/cache" ] || [ -d "$USER_HOME/.android/build-cache" ]; then
        run_clean_path "Cleaning Android SDK build cache" "contents" "$USER_HOME/.android/cache $USER_HOME/.android/build-cache"
    fi

    # 7. PHP Composer
    if command -v composer >/dev/null 2>&1; then
        run_cmd_task "Cleaning Composer cache" "$RUN_USER composer clear-cache"
    fi

    # 8. Flutter / Dart
    if command -v flutter >/dev/null 2>&1; then
        run_cmd_task "Cleaning Flutter cache" "$RUN_USER flutter cache clean"
    fi

    # 9. Docker / Podman
    if command -v docker >/dev/null 2>&1; then
        if docker system info >/dev/null 2>&1; then
            run_cmd_task "Pruning Docker system & unused volumes" "docker system prune -a --volumes -f" true
            run_cmd_task "Pruning Docker build cache" "docker builder prune -a -f" true
        else
            log "Docker daemon is not running. Skipping Docker prune."
        fi
    fi
    if command -v podman >/dev/null 2>&1; then
        run_cmd_task "Pruning Podman system" "podman system prune -a --volumes -f" true
    fi

    # 10. AI / Machine Learning Caches
    if [ -d "$USER_HOME/.cache/huggingface" ] || [ -d "$USER_HOME/.cache/torch" ]; then
        run_clean_path "Cleaning AI/ML temporary downloads & lock files" "contents" "$USER_HOME/.cache/huggingface/hub/tmp* $USER_HOME/.cache/torch"
    fi
}

# --- Banners & Summary ---

print_banner() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
  __  __               ____ _                            
 |  \/  | __ _  ___   / ___| | ___  __ _ _ __   ___ _ __ 
 | |\/| |/ _` |/ __| | |   | |/ _ \/ _` | '_ \ / _ \ '__|
 | |  | | (_| | (__  | |___| |  __/ (_| | | | |  __/ |   
 |_|  |_|\__,_|\___|  \____|_|\___|\__,_|_| |_|\___|_|   
EOF
    echo -e "${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${CYAN}   Universal System Cleaner & Updater (Pro Ultimate) ${NC}"
    echo -e "${YELLOW}   Version  :${NC} 3.0.0"
    echo -e "${YELLOW}   Platform :${NC} $OS_DISPLAY_INFO"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}   Mode     :${NC} ${RED}[DRY-RUN SIMULATION]${NC}"
    else
        echo -e "${YELLOW}   Mode     :${NC} Maintenance ($MODE)"
    fi
    echo -e "${YELLOW}   Disk Free:${NC} $(format_kb $INITIAL_FREE_KB)"
    echo -e "${YELLOW}   Log File :${NC} $LOG_FILE"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
}

print_summary() {
    FINAL_FREE_KB=$(get_free_disk_kb)
    local delta_disk_kb=0
    if [[ $FINAL_FREE_KB -gt $INITIAL_FREE_KB ]]; then
        delta_disk_kb=$((FINAL_FREE_KB - INITIAL_FREE_KB))
    fi

    echo ""
    echo ""
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${YELLOW}                 TASK EXECUTION SUMMARY             ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    for entry in "${SUMMARY_LOG[@]}"; do
        echo -e "$entry"
    done
    
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${YELLOW}               DISK SPACE SAVINGS REPORT            ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    printf "  ${CYAN}%-26s${NC} : %s\n" "Initial Free Space" "$(format_kb $INITIAL_FREE_KB)"
    printf "  ${CYAN}%-26s${NC} : %s\n" "Current Free Space" "$(format_kb $FINAL_FREE_KB)"
    if [[ "$DRY_RUN" == true ]]; then
        printf "  ${GREEN}%-26s${NC} : %s (Estimated)\n" "Potential Space Savings" "$(format_kb $TOTAL_FREED_KB)"
    else
        if [[ $delta_disk_kb -gt 0 ]]; then
            printf "  ${GREEN}%-26s${NC} : +%s  🎉\n" "Net Disk Space Reclaimed" "$(format_kb $delta_disk_kb)"
        fi
        printf "  ${GREEN}%-26s${NC} : %s\n" "Tracked Cleaned Files" "$(format_kb $TOTAL_FREED_KB)"
    fi
    echo -e "${BLUE}=====================================================${NC}"

    if [ ${#ERRORS_LOG[@]} -ne 0 ]; then
        echo -e "${RED}[!] Encountered ${#ERRORS_LOG[@]} warning(s)/error(s). Check $LOG_FILE for details.${NC}"
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${GREEN}✔ Dry run completed successfully! No files were modified.${NC}"
        else
            echo -e "${GREEN}✔ All cleaning and maintenance tasks completed successfully!${NC}"
        fi
    fi

    if [ "$UPDATES_AVAILABLE" = true ]; then
        echo ""
        echo -e "${CYAN}--- Updated Packages (Snapshot) ---${NC}"
        cat "$UPDATES_LIST_FILE"
        echo -e "${CYAN}-----------------------------------${NC}"
    fi
    echo ""
}

# --- Main Entry Point ---

main() {
    parse_arguments "$@"
    detect_distro
    setup_privileges

    # Ensure log file exists and is writable
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" 2>/dev/null || { echo "Cannot write to log file $LOG_FILE"; exit 1; }
    fi

    # Capture initial free space
    INITIAL_FREE_KB=$(get_free_disk_kb)

    calculate_total_steps
    print_banner

    log "Starting maintenance session (Mode: $MODE, DryRun: $DRY_RUN, InitialFree: $(format_kb $INITIAL_FREE_KB))..."

    # 1. Platform Specific Tasks
    case "$DISTRO" in
        macos)
            task_macos
            ;;
        ubuntu|debian|kali|linuxmint|pop)
            [[ "$MODE" != "dev" ]] && task_linux_system_clean
            [[ "$MODE" != "system" ]] && task_apt
            ;;
        fedora|rhel|centos|almalinux|rocky)
            [[ "$MODE" != "dev" ]] && task_linux_system_clean
            [[ "$MODE" != "system" ]] && task_dnf
            ;;
        arch|manjaro|endeavouros)
            [[ "$MODE" != "dev" ]] && task_linux_system_clean
            [[ "$MODE" != "system" ]] && task_pacman
            ;;
        opensuse*|sles)
            [[ "$MODE" != "dev" ]] && task_linux_system_clean
            [[ "$MODE" != "system" ]] && task_zypper
            ;;
        *)
            echo -e "${RED}[ERROR] Distribution '$DISTRO' is not supported.${NC}"
            log_error "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac

    # 2. Developer Tools & Environments (if not system-only mode)
    if [[ "$MODE" != "system" ]]; then
        run_dev_tools_cleanup
    fi

    # 3. Print Results & Storage Saved
    print_summary
}

main "$@"
