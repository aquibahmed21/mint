#!/usr/bin/env bash
# =====================================================================
#  Shared helpers for run1.sh, run2.sh and run-optional.sh
#  Do not run this file on its own.
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/mint-bundle"
LOG_DIR="$HOME/mint-setup-logs"
FAILED=()

have() { command -v "$1" >/dev/null 2>&1; }

# Start a run: refuse sudo, log everything to LOG_DIR, keep sudo alive.
init_run() {   # init_run <name>
    local name="$1"
    if [[ $EUID -eq 0 ]]; then
        echo "Do not run this with sudo. Run: bash $name.sh"
        exit 1
    fi
    mkdir -p "$LOG_DIR"
    exec > >(tee -a "$LOG_DIR/$name-$(date +%F_%H%M).log") 2>&1
    echo "=== $name started $(date) ==="
    echo "Log folder: $LOG_DIR"
    grep -qi "mint" /etc/os-release || echo "Warning: this does not look like Linux Mint."
    sudo -v || { echo "sudo is needed. Exiting."; exit 1; }
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

ask_yes() {   # ask_yes "question"  -> true only for y / Y
    local ans
    read -rp "$1 [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]]
}

apt_install() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Try all packages at once. If that fails, retry one by one so a single
# bad package name does not block the rest.
install_packages() {
    apt_install "$@" && return 0
    local pkg bad=()
    for pkg in "$@"; do
        apt_install "$pkg" >/dev/null 2>&1 || bad+=("$pkg")
    done
    if (( ${#bad[@]} )); then
        echo "Could not install: ${bad[*]}"
        return 1
    fi
}

# Download a .deb into a temp folder, install it, delete the folder.
install_deb() {   # install_deb <command to check> <url> <file name>
    local cmd="$1" url="$2" file="$3" dir rc
    if have "$cmd"; then
        echo "$cmd already installed. Skipping."
        return 0
    fi
    dir=$(mktemp -d) || return 1
    wget -q -O "$dir/$file" "$url" && apt_install "$dir/$file"
    rc=$?
    rm -rf "$dir"
    return $rc
}

copy_tree() {   # copy_tree <source folder> <destination folder>
    if [[ -d $1 ]]; then
        mkdir -p "$2" && cp -a "$1/." "$2/" && echo "copied $1 -> $2"
    else
        echo "skipped (not in bundle): $1"
    fi
}

run_step() {   # run_step "Title" function
    local title="$1"; shift
    echo
    echo "=============================================="
    echo "  $title"
    echo "=============================================="
    if "$@"; then
        echo "[ok] $title"
    else
        echo "[FAILED] $title"
        FAILED+=("$title")
    fi
}

print_summary() {
    echo
    echo "=============================================="
    if (( ${#FAILED[@]} == 0 )); then
        echo "  All steps finished."
    else
        echo "  These steps FAILED (logs in $LOG_DIR):"
        printf '    - %s\n' "${FAILED[@]}"
    fi
    echo "=============================================="
}
