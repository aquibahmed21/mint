#!/usr/bin/env bash
# =====================================================================
#  VPN - ProtonVPN (free plan), GUI app from Proton's official repository
#
#    bash optional/vpn.sh install   Add Proton's repository and install the GUI app
#    bash optional/vpn.sh status    Show whether it is installed
#    bash optional/vpn.sh purge     Remove the app and the repository
#
#  After install: open "Proton VPN" from the menu and sign in with a free
#  Proton account. Sign-in is interactive, so the script cannot do it.
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "vpn-$ACTION"

# Proton's official release package (adds their apt repository).
# Verify this URL against https://protonvpn.com/support/linux-vpn-debian-ubuntu if the download fails.
RELEASE_DEB_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
GUI_PKG=proton-vpn-gnome-desktop

install_vpn() {
    if dpkg -s "$GUI_PKG" >/dev/null 2>&1; then
        echo "Proton VPN is already installed."
        return 0
    fi
    local dir
    dir=$(mktemp -d) || return 1
    wget -q -O "$dir/release.deb" "$RELEASE_DEB_URL" && sudo dpkg -i "$dir/release.deb"
    local rc=$?
    rm -rf "$dir"
    (( rc == 0 )) || { echo "Could not add Proton's repository."; return 1; }

    sudo apt-get update || return 1
    apt_install "$GUI_PKG" || return 1
    echo "Open 'Proton VPN' from the menu and sign in with your free Proton account."
}

status_vpn() {
    if dpkg -s "$GUI_PKG" >/dev/null 2>&1; then
        echo "Proton VPN GUI: installed"
    else
        echo "Proton VPN GUI: not installed"
    fi
}

purge_vpn() {
    ask_yes "Remove Proton VPN and its repository?" || { echo "Cancelled."; return 0; }
    local pkgs=()
    mapfile -t pkgs < <(dpkg-query -W -f='${Package} ${db:Status-Status}\n' \
        | awk '$2 == "installed" && $1 ~ /^proton-?vpn/ {print $1}')
    if (( ${#pkgs[@]} )); then
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${pkgs[@]}" || return 1
    fi
    sudo rm -f /etc/apt/sources.list.d/protonvpn* 2>/dev/null
    sudo apt-get update
    echo "Proton VPN removed."
}

case "$ACTION" in
    install) run_step "Install ProtonVPN" install_vpn; record addon vpn ;;
    status)  status_vpn ;;
    purge)   run_step "Purge ProtonVPN" purge_vpn; unrecord addon vpn ;;
    *)       echo "Usage: bash optional/vpn.sh install|status|purge"; exit 1 ;;
esac

print_summary
