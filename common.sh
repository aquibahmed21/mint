#!/usr/bin/env bash
# =====================================================================
#  Shared helpers for every script in this kit.
#  Do not run this file on its own.
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/mint-bundle"
LOG_DIR="$HOME/mint-setup-logs"
MANIFEST="$HOME/.local/state/mint-setup/installed.tsv"   # what the kit installed
FAILED=()

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------
#  MANIFEST: a list of what the kit installed (not the dependencies)
#  One line per item:  <kind><TAB><name>
#  kind = apt | flatpak | npm | addon | tool
# ---------------------------------------------------------------------
record() {      # record <kind> <name>
    mkdir -p "$(dirname "$MANIFEST")"
    printf '%s\t%s\n' "$1" "$2" >> "$MANIFEST"
}

unrecord() {    # unrecord <kind> <name>
    [[ -f $MANIFEST ]] || return 0
    local tmp
    tmp=$(mktemp) || return 1
    grep -vxF "$(printf '%s\t%s' "$1" "$2")" "$MANIFEST" > "$tmp"
    mv "$tmp" "$MANIFEST"
}

# NVIDIA driver packages are never recorded or removed by the kit
is_driver_pkg() {
    [[ $1 =~ ^(nvidia|libnvidia|linux-modules-nvidia|xserver-xorg-video-nvidia) ]]
}

# ---------------------------------------------------------------------
#  RUN HANDLING
# ---------------------------------------------------------------------
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

ask_yes() {     # ask_yes "question"  -> true only for y / Y
    local ans
    read -rp "$1 [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]]
}

run_step() {    # run_step "Title" function [args]
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

# ---------------------------------------------------------------------
#  PACKAGE HELPERS (these record and unrecord automatically)
# ---------------------------------------------------------------------
apt_install() {
    local pkg new=()
    for pkg in "$@"; do
        [[ $pkg == -* || $pkg == */* ]] && continue      # skip options and local .deb paths
        dpkg -s "$pkg" >/dev/null 2>&1 || new+=("$pkg")  # only packages the kit adds
    done
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || return 1
    for pkg in "${new[@]}"; do
        is_driver_pkg "$pkg" || record apt "$pkg"
    done
}

apt_remove() {
    local pkg
    for pkg in "$@"; do
        is_driver_pkg "$pkg" && { echo "Refusing to remove driver package: $pkg"; return 1; }
    done
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" || return 1
    for pkg in "$@"; do unrecord apt "$pkg"; done
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

# Download a .deb into a temp folder, install it, record its package name.
install_deb() {   # install_deb <command to check> <url> <file name>
    local cmd="$1" url="$2" file="$3" dir pkg rc
    if have "$cmd"; then
        echo "$cmd already installed. Skipping."
        return 0
    fi
    dir=$(mktemp -d) || return 1
    wget -q -O "$dir/$file" "$url" || { rm -rf "$dir"; return 1; }
    pkg=$(dpkg-deb -f "$dir/$file" Package 2>/dev/null)
    apt_install "$dir/$file"
    rc=$?
    if (( rc == 0 )) && [[ -n $pkg ]]; then
        record apt "$pkg"
    fi
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

# ---------------------------------------------------------------------
#  MENU ENGINE for 04 (LLM tools) and 05 (tunnels / VPS)
#  The calling script must define: ITEMS, item_label, item_desc,
#  item_check, item_install, item_remove.
# ---------------------------------------------------------------------
menu_loop() {
    local action nums n id i st
    while true; do
        echo
        printf ' %-3s %-12s %-22s %s\n' "#" "STATUS" "ITEM" "WHAT IT IS"
        i=1
        for id in "${ITEMS[@]}"; do
            st="-"
            item_check "$id" && st="INSTALLED"
            printf ' %-3s %-12s %-22s %s\n' "$i" "$st" "$(item_label "$id")" "$(item_desc "$id")"
            i=$((i + 1))
        done
        echo
        read -rp "i 1 3 = install   |   r 2 = remove   |   q = quit: " action nums
        [[ -z $action || $action == q ]] && break
        for n in $nums; do
            if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ITEMS[@]} )); then
                id=${ITEMS[$((n - 1))]}
                case $action in
                    i) run_step "Install $(item_label "$id")" item_install "$id" ;;
                    r) run_step "Remove $(item_label "$id")"  item_remove "$id" ;;
                    *) echo "Use i (install) or r (remove)."; break ;;
                esac
            else
                echo "Skipping invalid number: $n"
            fi
        done
    done
    print_summary
}

# Command-line use: status | install <id>... | remove <id>... | (no args = menu)
items_cli() {
    local action="${1:-menu}" id
    shift || true
    case $action in
        menu)
            menu_loop ;;
        status)
            for id in "${ITEMS[@]}"; do
                printf '%-18s %s\n' "$id" "$(item_check "$id" && echo INSTALLED || echo not-installed)"
            done ;;
        install|remove)
            for id in "$@"; do
                if [[ $action == install ]]; then
                    run_step "Install $id" item_install "$id"
                else
                    run_step "Remove $id" item_remove "$id"
                fi
            done
            print_summary ;;
        *)
            echo "Usage: bash $0 [menu | status | install <id>... | remove <id>...]"
            echo "Ids: ${ITEMS[*]}"
            exit 1 ;;
    esac
}
