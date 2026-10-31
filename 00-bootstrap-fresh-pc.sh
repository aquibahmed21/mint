#!/usr/bin/env bash
# =====================================================================
#  00 - BOOTSTRAP. Run this FIRST on a fresh Linux Mint, before 01.
#
#  1. Installs git (if it is missing)
#  2. Downloads the kit from https://github.com/aquibahmed21/mint.git into ~/mint
#     (updates it if it is already there)
#  3. Makes every .sh file in the kit executable
#  4. Asks whether to start 01-base-install.sh now
#
#  Run as your normal user, NOT with sudo:
#      bash 00-bootstrap-fresh-pc.sh
#
#  Without copying this file first (the file must be on GitHub):
#      bash <(curl -fsSL https://raw.githubusercontent.com/aquibahmed21/mint/main/00-bootstrap-fresh-pc.sh)
# =====================================================================

set -euo pipefail

REPO_URL="https://github.com/aquibahmed21/mint.git"
TARGET="$HOME/mint"

# Asks on the keyboard even when this script is started through a pipe or <( )
ask_yes() {
    local ans=""
    if [[ -r /dev/tty ]]; then
        read -rp "$1 [y/N] " ans < /dev/tty || true
    else
        read -rp "$1 [y/N] " ans || true
    fi
    [[ $ans =~ ^[Yy]$ ]]
}

if [[ $EUID -eq 0 ]]; then
    echo "Do not run this with sudo. Run: bash 00-bootstrap-fresh-pc.sh"
    exit 1
fi

if ! grep -qi "mint" /etc/os-release; then
    echo "Warning: this does not look like Linux Mint."
fi

echo "== 1. git"
if command -v git >/dev/null 2>&1; then
    echo "git is already installed: $(git --version)"
else
    echo "Installing git..."
    sudo apt-get update
    sudo apt-get install -y git
fi

echo
echo "== 2. Kit from GitHub -> $TARGET"
if [[ -d $TARGET/.git ]]; then
    echo "Already cloned. Updating..."
    git -C "$TARGET" pull --ff-only
elif [[ -e $TARGET ]]; then
    echo "$TARGET exists but is not a git clone."
    echo "Move or rename it, then run this script again."
    exit 1
else
    git clone "$REPO_URL" "$TARGET"
fi

echo
echo "== 3. Making all scripts executable"
find "$TARGET" -path "$TARGET/.git" -prune -o -type f -name '*.sh' -exec chmod +x {} +
count=$(find "$TARGET" -path "$TARGET/.git" -prune -o -type f -name '*.sh' -print | wc -l)
echo "$count scripts are executable."

echo
echo "== Done"
echo "The first script to run is:"
echo "    bash $TARGET/01-base-install.sh"
echo
if ask_yes "Start 01-base-install.sh now?"; then
    exec bash "$TARGET/01-base-install.sh"
fi
echo "OK. Run it later with the command above."
