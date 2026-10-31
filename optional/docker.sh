#!/usr/bin/env bash
# =====================================================================
#  DOCKER - install, check or purge Docker Engine
#  Uses Docker's official repository (docker-ce), not Ubuntu's old docker.io.
#
#    bash optional/docker.sh install   Install Docker Engine + Compose + Buildx
#    bash optional/docker.sh status    Show what is installed and running
#    bash optional/docker.sh purge     Remove Docker, its images, containers and data
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "docker-$ACTION"

DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
# Packages that clash with Docker's official packages
CONFLICT_PKGS=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
KEYRING=/etc/apt/keyrings/docker.asc
SOURCE_FILE=/etc/apt/sources.list.d/docker.sources

installed_from() {   # prints the packages from the list that are installed
    local p
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 && echo "$p"
    done
}

install_docker() {
    local clash=()
    mapfile -t clash < <(installed_from "${CONFLICT_PKGS[@]}")
    if (( ${#clash[@]} )); then
        echo "Removing conflicting packages: ${clash[*]}"
        sudo apt-get remove -y "${clash[@]}" || return 1
    fi

    apt_install ca-certificates curl || return 1
    sudo install -m 0755 -d /etc/apt/keyrings || return 1
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$KEYRING" || return 1
    sudo chmod a+r "$KEYRING"

    # Remove any older source file that points at Docker's repository
    local f
    for f in /etc/apt/sources.list.d/*; do
        [[ $f == "$SOURCE_FILE" ]] && continue
        if grep -q "download.docker.com" "$f" 2>/dev/null; then
            sudo rm -f "$f" && echo "Removed older Docker source: $f"
        fi
    done

    local codename
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    sudo tee "$SOURCE_FILE" >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: $KEYRING
EOF

    sudo apt-get update || return 1
    apt_install "${DOCKER_PKGS[@]}" || return 1
    sudo systemctl enable --now docker containerd || return 1
    sudo usermod -aG docker "$USER"

    echo "Testing Docker with a small test image..."
    sudo docker run --rm hello-world || echo "Test failed. Check your internet, then run: sudo docker run --rm hello-world"
    echo "Log out and back in once so the 'docker' group works without sudo."
}

status_docker() {
    if have docker; then docker --version; else echo "Docker: not installed"; fi
    echo "Docker service: $(systemctl is-active docker 2>/dev/null)"
    if id -nG | tr ' ' '\n' | grep -qx docker; then
        echo "You are in the docker group: yes"
    else
        echo "You are in the docker group: no"
    fi
}

purge_docker() {
    echo "This removes Docker Engine AND all images, containers, volumes and networks."
    ask_yes "Continue?" || { echo "Cancelled."; return 0; }

    sudo systemctl disable --now docker docker.socket containerd 2>/dev/null
    local pkgs=()
    mapfile -t pkgs < <(installed_from "${DOCKER_PKGS[@]}" "${CONFLICT_PKGS[@]}")
    if (( ${#pkgs[@]} )); then
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${pkgs[@]}" || return 1
    fi
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
    sudo rm -f "$SOURCE_FILE" "$KEYRING" /etc/apt/keyrings/docker.gpg
    sudo gpasswd -d "$USER" docker >/dev/null 2>&1
    sudo apt-get update
    echo "Docker purged. Log out and back in to clear the docker group."
}

case "$ACTION" in
    install) run_step "Install Docker" install_docker; record addon docker ;;
    status)  status_docker ;;
    purge)   run_step "Purge Docker" purge_docker; unrecord addon docker ;;
    *)       echo "Usage: bash optional/docker.sh install|status|purge"; exit 1 ;;
esac

print_summary
