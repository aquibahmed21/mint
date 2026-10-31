#!/usr/bin/env bash
# =====================================================================
#  RUN 1 - base install. Run this FIRST on a fresh Linux Mint.
#  Removes bloat, updates, installs apps, the GPU driver and the add-ons,
#  then asks you to reboot. 02-after-reboot.sh starts by itself after your next login.
#      bash 01-base-install.sh
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---------------------------------------------------------------------
#  SETTINGS (1 = yes, 0 = no)
# ---------------------------------------------------------------------
INSTALL_CHROME=1
INSTALL_VSCODE=1
INSTALL_ONLYOFFICE=1
INSTALL_FLATPAKS=1
INSTALL_NODE=1
INSTALL_VIRTUALBOX=1       # optional/virtualbox.sh  (VirtualBox + extension pack)
INSTALL_VPN=1              # optional/vpn.sh         (ProtonVPN free, GUI)
INSTALL_DOCKER=0           # optional/docker.sh      (you don't use Docker)
INSTALL_CUDA=0             # optional/cuda.sh        (you don't use the CUDA toolkit)

# ---------------------------------------------------------------------
#  PACKAGES
# ---------------------------------------------------------------------
# Removed on purpose. Timeshift is NOT here: it is installed and used on your PC.
# PipeWire is NOT removed: it is your current audio server.
BLOAT=(
    gnome-2048 aisleriot atomix gnome-chess five-or-more hitori iagno
    gnome-klotski lightsoff gnome-mahjongg gnome-mines gnome-nibbles
    quadrapassel four-in-a-row gnome-robots gnome-sudoku swell-foop tali
    gnome-taquin gnome-tetravex
    empathy brasero sound-juicer totem pidgin firefox firefox-esr
    gimp hexchat hexchat-common thunderbird chromium
    'synaptic*' 'libreoffice*' 'transmission*' warpinator
    xed celluloid drawing pix hypnotix xviewer webapp-manager
    onboard fingwit mintreport mintwelcome
)

# From your installed-package list, plus the core tools the old scripts used.
BASE_PACKAGES=(
    linux-firmware intel-microcode build-essential curl wget git unzip
    linux-tools-common linux-tools-generic
    deepin-image-viewer bleachbit
    irqbalance preload gufw vlc mpv ffmpeg ffmpegthumbnailer sqlitebrowser default-jdk
    adb protobuf-compiler software-properties-common
    numlockx gedit subversion wine stress-ng samba
    ubuntu-restricted-extras lm-sensors gir1.2-nm-1.0 gir1.2-gtk-3.0 python3-gi python3-requests python3-pip
    imagemagick
    bluez blueman bluez-tools bluez-obexd rfkill
    tuned tuned-utils timeshift xreader
    remmina remmina-plugin-rdp remmina-plugin-vnc
    gamemode nvidia-settings
)

# Flatpak apps from your current PC (flatpak-apps list)
FLATPAK_APPS=(
    ai.lmstudio.lm-studio
    com.anydesk.Anydesk
    com.github.qarmin.czkawka
    com.github.tchx84.Flatseal
    com.github.wwmm.easyeffects
    com.keepsolid.VpnUnlimited
    com.leinardi.gst
    com.warlordsoftwares.youtube-downloader-4ktube
    fr.handbrake.ghb
    io.freetubeapp.FreeTube
    io.github.aandrew_me.ytdn
    net.conceptualspace.prunr
    org.mozilla.firefox
    org.rncbc.qpwgraph
)

NPM_GLOBALS=(browserify ts-protoc-gen typescript)

# ---------------------------------------------------------------------
#  STEPS
# ---------------------------------------------------------------------
stage_kit() {
    # Copy the kit to ~/mint-setup so 02-after-reboot.sh still works after reboot
    # even if this drive is not mounted yet.
    local dest="$HOME/mint-setup"
    [[ $SCRIPT_DIR == "$dest" ]] && return 0
    mkdir -p "$dest" && cp -a "$SCRIPT_DIR/." "$dest/" && echo "Kit copied to $dest"
}

addon() {   # addon <name> <action>  e.g.  addon docker install
    bash "$SCRIPT_DIR/optional/$1.sh" "$2"
}

remove_bloat() {
    # Only remove packages that are actually installed (apt aborts the whole
    # purge if one name is unknown).
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

install_gpu_driver() {
    # Installs the driver Ubuntu recommends for your GPU (RTX 3060 -> nvidia-driver-595-open)
    have ubuntu-drivers || { echo "ubuntu-drivers not found."; return 1; }
    sudo ubuntu-drivers install
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
            if sudo npm install -g "$pkg"; then record npm "$pkg"; else rc=1; fi
        fi
    done
    return $rc
}

install_flatpaks() {
    have flatpak || apt_install flatpak || return 1
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    local app rc=0
    for app in "${FLATPAK_APPS[@]}"; do
        flatpak info "$app" >/dev/null 2>&1 && continue
        if sudo flatpak install -y flathub "$app"; then record flatpak "$app"; else echo "Failed: $app"; rc=1; fi
    done
    return $rc
}

schedule_run2() {
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/mint-setup-run2.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Mint setup - run2
Exec=x-terminal-emulator -e bash "$HOME/mint-setup/02-after-reboot.sh"
X-GNOME-Autostart-enabled=true
EOF
    echo "02-after-reboot.sh will open by itself after your next login."
}

# ---------------------------------------------------------------------
#  MAIN
# ---------------------------------------------------------------------
main() {
    init_run 01-base-install
    run_step "Stage setup kit to ~/mint-setup" stage_kit
    run_step "Remove bloatware"                remove_bloat
    run_step "Update system"                   update_system
    run_step "Base packages"                   install_base_packages
    run_step "GPU driver (recommended)"        install_gpu_driver
    (( INSTALL_CHROME ))       && run_step "Google Chrome"           install_chrome
    (( INSTALL_VSCODE ))       && run_step "VS Code"                 install_vscode
    (( INSTALL_ONLYOFFICE ))   && run_step "OnlyOffice"              install_onlyoffice
    (( INSTALL_NODE ))         && run_step "Node.js and npm"         install_node
    (( INSTALL_FLATPAKS ))     && run_step "Flatpak apps"            install_flatpaks
    (( INSTALL_VIRTUALBOX ))   && run_step "VirtualBox + extension"  addon virtualbox install
    (( INSTALL_VPN ))          && run_step "ProtonVPN (free GUI)"    addon vpn install
    run_step "FTP server (required)"           bash "$SCRIPT_DIR/core/ftp.sh" install
    run_step "Terminal prompt (required)"      bash "$SCRIPT_DIR/core/terminal.sh" install
    (( INSTALL_DOCKER ))       && run_step "Docker"                  addon docker install
    (( INSTALL_CUDA ))         && run_step "CUDA toolkit"            addon cuda install
    run_step "Schedule run2 after login"       schedule_run2

    print_summary
    if ask_yes "Reboot now? (02-after-reboot.sh will start after you log in)"; then
        sudo reboot
    fi
}

main "$@"
