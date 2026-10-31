#!/usr/bin/env bash
# =====================================================================
#  CUDA TOOLKIT - install, check or purge NVIDIA's developer toolkit
#
#  WHAT IT IS: developer tools for writing and compiling GPU programs
#  (nvcc compiler, profilers, headers). Only programmers building CUDA
#  code need it.
#  NOT NEEDED FOR: games, the desktop, video, or LM Studio. LM Studio
#  ships its own GPU runtime, and the NVIDIA DRIVER (which you already have)
#  is what those apps use. The driver is never removed by this script.
#
#    bash optional/cuda.sh install   Install the Ubuntu CUDA toolkit package
#    bash optional/cuda.sh status    Show driver and toolkit versions
#    bash optional/cuda.sh purge     Remove the toolkit (keeps the driver)
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "cuda-$ACTION"

CUDA_PKG=nvidia-cuda-toolkit
# Packages that belong to the toolkit (developer files, profilers)
TOOLKIT_PATTERNS=('nvidia-cuda-*' nvidia-profiler nvidia-visual-profiler nvidia-opencl-dev libnvidia-ml-dev)
# Safety stop: if a purge would touch any of these, nothing is removed.
DRIVER_GUARD='^(nvidia-driver-|nvidia-kernel-|nvidia-utils-|libnvidia-(gl|compute|decode|encode|fbc|egl|cfg|extra|common)|xserver-xorg-video-nvidia)'

toolkit_installed_pkgs() {
    local installed pattern pkg
    installed=$(dpkg-query -W -f='${Package} ${db:Status-Status}\n' | awk '$2 == "installed" {print $1}')
    for pattern in "${TOOLKIT_PATTERNS[@]}"; do
        for pkg in $installed; do
            # shellcheck disable=SC2053  # the pattern is meant to glob
            [[ $pkg == $pattern ]] && echo "$pkg"
        done
    done | sort -u
}

install_cuda() {
    if ! have nvidia-smi; then
        echo "No NVIDIA driver found (nvidia-smi missing). Install the driver first."
        return 1
    fi
    install_packages "$CUDA_PKG" || return 1
    check_cuda
}

check_cuda() {
    if have nvcc; then
        nvcc --version | tail -n 2
    else
        echo "nvcc not found. The toolkit may not be installed."
        return 1
    fi
}

status_cuda() {
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "NVIDIA driver: not found"
    if have nvcc; then
        nvcc --version | tail -n 2
    else
        echo "CUDA toolkit: not installed"
    fi
}

purge_cuda() {
    local pkgs=()
    mapfile -t pkgs < <(toolkit_installed_pkgs)
    if (( ${#pkgs[@]} == 0 )); then
        echo "CUDA toolkit packages are not installed."
        return 0
    fi

    echo "Toolkit packages found:"
    printf '  %s\n' "${pkgs[@]}"

    # Ask apt what else it would remove, and stop if the GPU driver is in that list
    local extra
    extra=$(sudo apt-get -s purge --auto-remove "${pkgs[@]}" 2>/dev/null | awk '/^Remv /{print $2}')
    echo "apt would also remove:"
    if [[ -n $extra ]]; then printf '  %s\n' $extra; else echo "  (nothing else)"; fi

    if echo "$extra" | grep -Eq "$DRIVER_GUARD"; then
        echo "STOP: this would remove GPU driver packages. Nothing was changed."
        return 1
    fi

    ask_yes "Remove the CUDA toolkit now? (the NVIDIA driver stays)" || { echo "Cancelled."; return 0; }
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove "${pkgs[@]}" || return 1
    sudo apt-get clean
    echo "CUDA toolkit removed. The NVIDIA driver is still installed."
}

case "$ACTION" in
    install) run_step "Install CUDA toolkit" install_cuda; record addon cuda ;;
    status)  status_cuda ;;
    purge)   run_step "Purge CUDA toolkit" purge_cuda; unrecord addon cuda ;;
    *)       echo "Usage: bash optional/cuda.sh install|status|purge"; exit 1 ;;
esac

print_summary
