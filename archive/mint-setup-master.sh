#!/usr/bin/env bash
# =====================================================================
#  Linux Mint fresh-install master setup
#
#  Run as your normal user, NOT with sudo:
#      bash mint-setup-master.sh
#  The script asks for your sudo password when it needs it.
#  Everything is also saved to ~/mint-setup.log.
#  A failed step is reported at the end. The other steps still run.
# =====================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/mint-setup.log"

# ---------------------------------------------------------------------
#  SETTINGS  (1 = yes, 0 = no)
# ---------------------------------------------------------------------
INSTALL_VIRTUALBOX=1
BLACKLIST_KVM=1            # VirtualBox needs KVM off. Set 0 if you use KVM/QEMU.
INSTALL_AUTO_CPUFREQ=0     # Laptop power manager. If 1, the tuned profile is not applied.
TUNED_PROFILE="throughput-performance"
ENABLE_GRUB_CURSOR_OFF=0   # Hides the text-console cursor.
BLUETOOTH_AUTO_ENABLE=0    # Power Bluetooth on at boot.
INSTALL_NODE=1
INSTALL_APPLETS=1
RESTORE_DCONF=0            # 1 = load $SCRIPT_DIR/my_dconf. This overwrites ALL desktop settings.

# ---------------------------------------------------------------------
#  PACKAGES
# ---------------------------------------------------------------------
# Apps removed on purpose (as in your old list). Patterns are matched
# against installed packages, so names that are not installed are skipped.
BLOAT=(
    gnome-2048 aisleriot atomix gnome-chess five-or-more hitori iagno
    gnome-klotski lightsoff gnome-mahjongg gnome-mines gnome-nibbles
    quadrapassel four-in-a-row gnome-robots gnome-sudoku swell-foop tali
    gnome-taquin gnome-tetravex
    empathy brasero sound-juicer totem pidgin firefox firefox-esr
    gimp hexchat hexchat-common thunderbird chromium
    'synaptic*' 'libreoffice*' timeshift 'transmission*' warpinator
    xed celluloid drawing pix hypnotix xviewer webapp-manager
    onboard fingwit mintreport mintwelcome
)

# Installed with one apt call. If that fails, each package is retried alone.
BASE_PACKAGES=(
    linux-firmware intel-microcode build-essential curl wget git unzip
    linux-tools-common linux-tools-generic
    deepin-image-viewer bleachbit
    irqbalance preload gufw vlc mpv sqlitebrowser default-jdk
    adb protobuf-compiler software-properties-common
    numlockx gedit subversion wine stress-ng samba
    ubuntu-restricted-extras lm-sensors gir1.2-nm-1.0
    gir1.2-gtk-3.0 python3-gi python3-requests
    imagemagick ffmpeg
    bluez blueman bluez-tools bluez-obexd rfkill
    tuned tuned-utils
)

FLATPAK_APPS=(com.leinardi.gst)
NPM_GLOBALS=(browserify ts-protoc-gen typescript)

# ---------------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------------
FAILED=()

have() { command -v "$1" >/dev/null 2>&1; }

apt_install() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Try all packages at once. If that fails, install them one by one so a
# single bad package name does not block the rest.
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

# Download a .deb to a temp folder, install it, then delete the folder.
install_deb() {   # install_deb <command-to-check> <url> <file-name>
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

# ---------------------------------------------------------------------
#  STEPS
# ---------------------------------------------------------------------
remove_bloat() {
    # Find which installed packages match the BLOAT patterns (apt aborts
    # the whole purge if even one name is unknown, so filter first).
    local installed=() to_remove=() pattern pkg
    mapfile -t installed < <(dpkg-query -W -f='${Package} ${db:Status-Status}\n' | awk '$2 == "installed" {print $1}')
    for pattern in "${BLOAT[@]}"; do
        for pkg in "${installed[@]}"; do
            # shellcheck disable=SC2053  # the pattern is meant to glob
            [[ $pkg == $pattern ]] && to_remove+=("$pkg")
        done
    done
    if (( ${#to_remove[@]} == 0 )); then
        echo "Nothing to remove."
        return 0
    fi
    echo "Removing: ${to_remove[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${to_remove[@]}"
}

update_system() {
    sudo apt-get update || return 1
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade || return 1
    sudo apt-get -y autoremove
    sudo apt-get clean
}

install_base_packages() {
    install_packages "${BASE_PACKAGES[@]}"
}

install_drivers() {
    if have ubuntu-drivers; then
        sudo ubuntu-drivers autoinstall
    else
        echo "ubuntu-drivers not found. Use Driver Manager instead."
    fi
}

install_chrome() {
    install_deb google-chrome \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        google-chrome-stable_current_amd64.deb
}

install_onlyoffice() {
    install_deb onlyoffice-desktopeditors \
        https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb \
        onlyoffice-desktopeditors_amd64.deb
}

install_vscode() {
    if have code; then
        echo "VS Code already installed. Skipping."
        return 0
    fi
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor \
        | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null || return 1
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null || return 1
    sudo apt-get update || return 1
    apt_install code
}

install_node() {
    if have node && have npm; then
        echo "Node.js already installed. Skipping."
    else
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || return 1
        apt_install nodejs || return 1
    fi
    local pkg rc=0
    for pkg in "${NPM_GLOBALS[@]}"; do
        if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
            echo "npm package $pkg already installed."
        else
            sudo npm install -g "$pkg" || rc=1
        fi
    done
    return $rc
}

tune_cpu() {
    # Kernel / memory settings
    sudo tee /etc/sysctl.d/99-performance.conf >/dev/null <<'EOF'
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.vfs_cache_pressure=50
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
net.core.netdev_max_backlog=250000
kernel.sched_min_granularity_ns=10000000
kernel.sched_wakeup_granularity_ns=15000000
EOF
    sudo sysctl --system >/dev/null || return 1

    sudo systemctl enable --now irqbalance preload 2>/dev/null || echo "irqbalance/preload not available. Skipped."

    # Power profile (tuned). Skipped when auto-cpufreq is used instead.
    sudo systemctl enable --now tuned.service || return 1
    if (( ! INSTALL_AUTO_CPUFREQ )); then
        sudo tuned-adm profile "$TUNED_PROFILE" || return 1
    fi

    # Turbo boost on, if the CPU exposes these switches
    local cpu=/sys/devices/system/cpu
    [[ -f $cpu/intel_pstate/no_turbo ]] && echo 0 | sudo tee "$cpu/intel_pstate/no_turbo" >/dev/null
    [[ -f $cpu/cpufreq/boost ]] && echo 1 | sudo tee "$cpu/cpufreq/boost" >/dev/null
    return 0
}

grub_cursor_off() {
    local grub=/etc/default/grub param="vt.global_cursor_default=0"
    if grep -q "$param" "$grub"; then
        echo "Already set."
        return 0
    fi
    sudo cp "$grub" "$grub.bak" || return 1
    sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"/" "$grub" || return 1
    grep -q "$param" "$grub" || { echo "Could not edit $grub. Backup is $grub.bak"; return 1; }
    sudo update-grub
}

install_auto_cpufreq() {
    have auto-cpufreq && { echo "auto-cpufreq already installed."; return 0; }
    local dir rc
    dir=$(mktemp -d) || return 1
    git clone --depth 1 https://github.com/AdnanHodzic/auto-cpufreq.git "$dir/auto-cpufreq" \
        && (cd "$dir/auto-cpufreq" && sudo ./auto-cpufreq-installer -i)
    rc=$?
    rm -rf "$dir"
    return $rc
}

setup_flatpak() {
    have flatpak || apt_install flatpak || return 1
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    sudo flatpak install -y flathub "${FLATPAK_APPS[@]}"
}

install_virtualbox() {
    apt_install virtualbox virtualbox-dkms dkms "linux-headers-$(uname -r)" || return 1
    if (( BLACKLIST_KVM )); then
        printf 'blacklist kvm\nblacklist kvm_intel\nblacklist kvm_amd\n' \
            | sudo tee /etc/modprobe.d/blacklist-kvm.conf >/dev/null
        sudo update-initramfs -u
    fi
    sudo modprobe vboxdrv || echo "vboxdrv not loaded yet. A reboot should fix it."
}

add_user_groups() {
    local group
    for group in vboxusers sambashare; do
        if getent group "$group" >/dev/null; then
            sudo usermod -aG "$group" "$USER"
        else
            echo "Group $group does not exist. Skipped."
        fi
    done
}

setup_firewall() {
    sudo ufw default deny incoming || return 1
    sudo ufw default allow outgoing || return 1
    sudo ufw allow samba || return 1
    sudo ufw --force enable
}

enable_services() {
    sudo systemctl restart smbd nmbd || return 1
    sudo systemctl enable --now bluetooth || return 1
    if (( BLUETOOTH_AUTO_ENABLE )); then
        sudo sed -i 's/^#\?AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    fi
}

install_applets() {
    local applet_dir="$HOME/.local/share/cinnamon/applets"
    local tmp rc=0 uuid entry url sub repo src
    mkdir -p "$applet_dir" || return 1
    tmp=$(mktemp -d) || return 1

    # Applet UUID -> "repo URL|folder inside repo (. = repo root)"
    # These repos are public, so no GitHub login is needed.
    local -A applets=(
        ["commandLauncher@scollins"]="https://github.com/linuxmint/cinnamon-spices-applets.git|commandLauncher@scollins"
        ["force-quit@cinnamon.org"]="https://github.com/linuxmint/cinnamon-spices-applets.git|force-quit@cinnamon.org"
        ["ssm@Severga"]="https://github.com/Severga/cinnamon-ssm-applet.git|."
        ["uptime@vatanuki.kun"]="https://github.com/VatanukiKlaus/cinnamon-uptime-applet.git|uptime@vatanuki.kun"
        ["temperature@fevimu"]="https://github.com/fevimu/cinnamon-temperature.git|temperature@fevimu"
        ["weather@mockturtl"]="https://github.com/mockturtl/cinnamon-weather.git|weather@mockturtl"
    )

    for uuid in "${!applets[@]}"; do
        entry=${applets[$uuid]}
        url=${entry%%|*}
        sub=${entry#*|}
        repo=$(basename "$url" .git)

        # Clone each repo once, even when several applets share it
        if [[ ! -d $tmp/$repo ]]; then
            git clone --depth 1 "$url" "$tmp/$repo" || { echo "Clone failed: $url"; rc=1; continue; }
        fi

        src="$tmp/$repo/$sub"
        [[ $sub == "." ]] && src="$tmp/$repo"

        if [[ -d $src ]]; then
            rm -rf "$applet_dir/$uuid"
            cp -r "$src" "$applet_dir/$uuid" && rm -rf "$applet_dir/$uuid/.git"
            echo "Installed $uuid"
        else
            echo "Missing folder for $uuid"
            rc=1
        fi
    done

    rm -rf "$tmp"
    echo "Restart Cinnamon to load applets: press Alt+F2, type r, press Enter."
    return $rc
}

restore_dconf() {
    local file="$SCRIPT_DIR/my_dconf"
    if [[ ! -f $file ]]; then
        echo "No $file found. Skipped."
        return 0
    fi
    dconf load / < "$file"
}

# ---------------------------------------------------------------------
#  MAIN
# ---------------------------------------------------------------------
preflight() {
    if [[ $EUID -eq 0 ]]; then
        echo "Do not run this with sudo. Run: bash $0"
        exit 1
    fi
    if ! grep -qi "mint" /etc/os-release; then
        echo "Warning: this does not look like Linux Mint. Continue anyway? [y/N]"
        read -r ans
        [[ $ans =~ ^[Yy]$ ]] || exit 1
    fi
    sudo -v || { echo "sudo is needed. Exiting."; exit 1; }
    # Keep the sudo timestamp fresh while the script runs
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

summary() {
    echo
    echo "=============================================="
    if (( ${#FAILED[@]} == 0 )); then
        echo "  All steps finished."
    else
        echo "  These steps FAILED (details in $LOG_FILE):"
        printf '    - %s\n' "${FAILED[@]}"
    fi
    echo "=============================================="
    read -rp "Reboot now? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] && sudo reboot
}

main() {
    preflight
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "Log: $LOG_FILE  ($(date))"

    run_step "Remove bloatware"                 remove_bloat
    run_step "Update system"                    update_system
    run_step "Install base packages"            install_base_packages
    run_step "Drivers"                          install_drivers
    run_step "Google Chrome"                    install_chrome
    run_step "VS Code"                          install_vscode
    run_step "OnlyOffice"                       install_onlyoffice
    (( INSTALL_NODE ))         && run_step "Node.js and npm tools"  install_node
    run_step "CPU and kernel tuning"            tune_cpu
    (( ENABLE_GRUB_CURSOR_OFF )) && run_step "GRUB: cursor off"     grub_cursor_off
    (( INSTALL_AUTO_CPUFREQ ))   && run_step "auto-cpufreq"         install_auto_cpufreq
    run_step "Flatpak apps"                     setup_flatpak
    (( INSTALL_VIRTUALBOX ))   && run_step "VirtualBox"             install_virtualbox
    run_step "User groups"                      add_user_groups
    run_step "Firewall (ufw)"                   setup_firewall
    run_step "Samba and Bluetooth services"     enable_services
    (( INSTALL_APPLETS ))      && run_step "Cinnamon applets"      install_applets
    (( RESTORE_DCONF ))        && run_step "Desktop settings (dconf)" restore_dconf

    summary
}

main "$@"
