#!/usr/bin/env bash
# =====================================================================
#  RUN 2 - tuning and your desktop. Starts by itself after the first
#  login following 01-base-install.sh. You can also run it any time:
#      bash ~/mint-setup/02-after-reboot.sh
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---------------------------------------------------------------------
#  SETTINGS (1 = yes, 0 = no)
# ---------------------------------------------------------------------
ENABLE_CPU_PERFORMANCE=1   # performance governor + turbo on, kept across reboots (turbo is OFF on your PC now)
TUNED_PROFILE="throughput-performance"
JOURNAL_MAX="200M"         # limits system log size (it is 449 MB now)
CLEAN_OLD_KERNELS=1        # removes old kernels; the running one is kept
ENABLE_GRUB_CURSOR_OFF=1   # already set on your PC, so this is a no-op there
RESTORE_DESKTOP=1          # theme, applets, extensions, fonts, panels, shortcuts from mint-bundle
BLUETOOTH_AUTO_ENABLE=0

# ---------------------------------------------------------------------
#  STEPS
# ---------------------------------------------------------------------
cpu_performance() {
    sudo tee /etc/systemd/system/mint-cpu-performance.service >/dev/null <<'EOF'
[Unit]
Description=CPU performance governor and turbo boost
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo performance | tee /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor >/dev/null; [ -e /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo; [ -e /sys/devices/system/cpu/cpufreq/boost ] && echo 1 > /sys/devices/system/cpu/cpufreq/boost; true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload || return 1
    sudo systemctl enable --now mint-cpu-performance.service || return 1
    echo "Turbo now: $(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo n/a) (0 = turbo on)"
}

tune_system() {
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

    sudo mkdir -p /etc/systemd/journald.conf.d || return 1
    printf '[Journal]\nSystemMaxUse=%s\n' "$JOURNAL_MAX" | sudo tee /etc/systemd/journald.conf.d/size.conf >/dev/null
    sudo systemctl restart systemd-journald

    sudo systemctl enable --now irqbalance 2>/dev/null || echo "irqbalance not available."
    sudo systemctl enable --now preload 2>/dev/null || echo "preload not available."
    sudo systemctl enable --now tuned.service || return 1
    sudo tuned-adm profile "$TUNED_PROFILE" || return 1
}

nvidia_tuning() {
    have nvidia-smi || { echo "No NVIDIA driver found. Skipped."; return 0; }
    install_packages nvidia-persistenced || return 1
    sudo systemctl enable --now nvidia-persistenced
}

clean_kernels() {
    sudo apt-get autoremove --purge -y
}

grub_cursor_off() {
    local grub=/etc/default/grub param="vt.global_cursor_default=0"
    if grep -q "$param" "$grub"; then
        echo "Already set."
        return 0
    fi
    sudo cp "$grub" "$grub.bak" || return 1
    sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"/" "$grub" || return 1
    grep -q "$param" "$grub" || { echo "Could not edit $grub. Backup: $grub.bak"; return 1; }
    sudo update-grub
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

restore_desktop() {
    local b="$BUNDLE_DIR"
    if [[ ! -d $b ]]; then
        echo "No mint-bundle folder at $b."
        echo "Run 00-export-from-old-pc.sh on your current PC, then copy the bundle here."
        return 1
    fi

    # Applets and extensions first, so the panel layout loaded below finds them
    copy_tree "$b/cinnamon/applets"    "$HOME/.local/share/cinnamon/applets"
    copy_tree "$b/cinnamon/extensions" "$HOME/.local/share/cinnamon/extensions"
    copy_tree "$b/cinnamon/desklets"   "$HOME/.local/share/cinnamon/desklets"
    copy_tree "$b/themes"              "$HOME/.themes"
    copy_tree "$b/icons"               "$HOME/.icons"
    copy_tree "$b/fonts"               "$HOME/.fonts"
    have fc-cache && fc-cache -f >/dev/null
    copy_tree "$b/config/autostart"    "$HOME/.config/autostart"
    copy_tree "$b/config/gtk-3.0"      "$HOME/.config/gtk-3.0"
    [[ -f $b/config/mimeapps.list ]] && cp "$b/config/mimeapps.list" "$HOME/.config/mimeapps.list"

    # Only the sections you use. Full dconf restore is in 03-optional-extras.sh.
    local rc=0 f
    for f in "cinnamon.ini:/org/cinnamon/" \
             "gnome-desktop.ini:/org/gnome/desktop/" \
             "media-keys.ini:/org/gnome/settings-daemon/plugins/media-keys/" \
             "nemo.ini:/org/nemo/" \
             "x.ini:/org/x/"; do
        local file="${f%%:*}" path="${f#*:}"
        if [[ -f $b/dconf/$file ]]; then
            dconf load "$path" < "$b/dconf/$file" && echo "loaded $path" || rc=1
        fi
    done
    echo "Log out and back in (or restart Cinnamon: Alt+F2, type r) to apply everything."
    return $rc
}

# ---------------------------------------------------------------------
#  MAIN
# ---------------------------------------------------------------------
main() {
    init_run 02-after-reboot
    (( ENABLE_CPU_PERFORMANCE )) && run_step "CPU: performance + turbo" cpu_performance
    run_step "Kernel, memory, journal, power profile" tune_system
    run_step "NVIDIA persistence daemon"            nvidia_tuning
    (( CLEAN_OLD_KERNELS ))      && run_step "Remove old kernels"  clean_kernels
    (( ENABLE_GRUB_CURSOR_OFF )) && run_step "GRUB: cursor off"    grub_cursor_off
    run_step "Firewall (ufw)"                       setup_firewall
    run_step "Samba and Bluetooth"                  enable_services
    run_step "User groups"                          add_user_groups
    (( RESTORE_DESKTOP )) && run_step "Restore desktop from mint-bundle" restore_desktop

    # Stop auto-starting run2 once everything worked. If something failed,
    # it stays, so run2 runs again after the next login.
    if (( ${#FAILED[@]} == 0 )); then
        rm -f "$HOME/.config/autostart/mint-setup-run2.desktop"
    fi
    print_summary
}

main "$@"
