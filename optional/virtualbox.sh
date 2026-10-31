#!/usr/bin/env bash
# =====================================================================
#  VIRTUALBOX - install, check or purge VirtualBox + Extension Pack
#
#    bash optional/virtualbox.sh install   Install VirtualBox, guest additions, extension pack
#    bash optional/virtualbox.sh status    Show version, extension pack and module state
#    bash optional/virtualbox.sh purge     Remove VirtualBox (your VMs are NOT touched)
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "virtualbox-$ACTION"

# KVM and VirtualBox cannot use the CPU's virtualization at the same time.
# 1 = disable KVM so VirtualBox works. 0 = keep KVM (VirtualBox may then fail to start VMs).
BLACKLIST_KVM=1
BLACKLIST_FILE=/etc/modprobe.d/blacklist-kvm.conf
VBOX_PKGS=(virtualbox virtualbox-dkms dkms virtualbox-guest-additions-iso)
EXTPACK_PKG=virtualbox-ext-pack

install_virtualbox() {
    apt_install "${VBOX_PKGS[@]}" "linux-headers-$(uname -r)" || return 1

    # Try to accept the extension pack license in advance (so no prompt)
    echo "$EXTPACK_PKG $EXTPACK_PKG/license select true" | sudo debconf-set-selections
    if ! apt_install "$EXTPACK_PKG"; then
        echo
        echo "The extension pack is not in apt on this system."
        echo "Manual option: download the .vbox-extpack file that matches"
        echo "'VBoxManage --version' from virtualbox.org, then run:"
        echo "    sudo VBoxManage extpack install --replace <file>.vbox-extpack"
        echo
    fi

    if (( BLACKLIST_KVM )); then
        printf 'blacklist kvm\nblacklist kvm_intel\nblacklist kvm_amd\n' \
            | sudo tee "$BLACKLIST_FILE" >/dev/null
        sudo update-initramfs -u
    fi

    sudo modprobe vboxdrv 2>/dev/null \
        || echo "vboxdrv is not loaded yet. Reboot once, then run: bash optional/virtualbox.sh status"
    sudo usermod -aG vboxusers "$USER"
}

status_virtualbox() {
    if have VBoxManage; then
        echo "VirtualBox version: $(VBoxManage --version)"
        VBoxManage list extpacks 2>/dev/null | head -n 5
    else
        echo "VirtualBox: not installed"
    fi
    if lsmod | grep -q '^vboxdrv '; then echo "vboxdrv module: loaded"; else echo "vboxdrv module: NOT loaded"; fi
    if lsmod | grep -q '^kvm '; then echo "KVM loaded: yes (conflicts with VirtualBox)"; else echo "KVM loaded: no"; fi
}

purge_virtualbox() {
    echo "This removes VirtualBox and its extension pack. Your VMs in ~/VirtualBox VMs are NOT deleted."
    ask_yes "Continue?" || { echo "Cancelled."; return 0; }

    local pkgs=()
    mapfile -t pkgs < <(
        for p in virtualbox virtualbox-dkms virtualbox-ext-pack virtualbox-guest-additions-iso virtualbox-qt; do
            dpkg -s "$p" >/dev/null 2>&1 && echo "$p"
        done
    )
    if (( ${#pkgs[@]} )); then
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${pkgs[@]}" || return 1
    fi
    sudo rm -f "$BLACKLIST_FILE"
    sudo update-initramfs -u
    sudo gpasswd -d "$USER" vboxusers >/dev/null 2>&1
    echo "VirtualBox removed. Reboot to bring KVM back."
}

case "$ACTION" in
    install) run_step "Install VirtualBox" install_virtualbox; record addon virtualbox ;;
    status)  status_virtualbox ;;
    purge)   run_step "Purge VirtualBox" purge_virtualbox; unrecord addon virtualbox ;;
    *)       echo "Usage: bash optional/virtualbox.sh install|status|purge"; exit 1 ;;
esac

print_summary
