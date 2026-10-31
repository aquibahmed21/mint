#!/usr/bin/env bash
# =====================================================================
#  Linux Mint system inventory (READ-ONLY)
#
#  Collects hardware, software, desktop theme/applet/shortcut settings
#  into one log file so the setup scripts can be planned from real data.
#  It changes nothing on the system. Run as your normal user:
#      bash tools/inventory.sh
#  Output: ~/mint-inventory/<date>/inventory.log  (+ raw dump files)
# =====================================================================

set -u

OUT="$HOME/mint-inventory/$(date +%F_%H%M)"
LOG="$OUT/inventory.log"
mkdir -p "$OUT" || exit 1

have() { command -v "$1" >/dev/null 2>&1; }

section() {
    printf '\n\n##################################################\n# %s\n##################################################\n' "$1" >> "$LOG"
}

# run "label" command args...  -> writes label + output + exit status to log
run() {
    local label="$1"; shift
    printf '\n--- %s\n$ %s\n' "$label" "$*" >> "$LOG"
    "$@" >> "$LOG" 2>&1 || printf '[command failed or not available, exit %s]\n' "$?" >> "$LOG"
}

# dump_to <file> command...  -> saves large output to its own file
dump_to() {
    local file="$1"; shift
    "$@" > "$OUT/$file" 2>&1 || echo "[failed: $*]" > "$OUT/$file"
    printf '\n--- saved to %s (%s lines)\n' "$file" "$(wc -l < "$OUT/$file")" >> "$LOG"
}

echo "Collecting inventory into $OUT ..."

# ---------------------------------------------------------------------
section "1. GENERAL"
run "date"          date
run "hostname"      hostname
run "user"          whoami
run "uptime"        uptime -p
run "os-release"    cat /etc/os-release
run "kernel"        uname -a
run "desktop env"   printenv XDG_CURRENT_DESKTOP
run "session type"  printenv XDG_SESSION_TYPE
run "cinnamon ver"  cinnamon --version
run "shell"         printenv SHELL
run "chassis"       hostnamectl chassis
run "dmi (vendor/model)" bash -c 'for f in sys_vendor product_name product_version; do echo "$f: $(cat /sys/class/dmi/id/$f 2>/dev/null)"; done'

# ---------------------------------------------------------------------
section "2. CPU"
run "lscpu"         lscpu
run "cpu flags (virtualization & features)" bash -c "grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -E '^(vmx|svm|avx2|avx512f|aes|sse4_2)$' | tr '\n' ' '; echo"
run "scaling governor" bash -c 'cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c'
run "available governors" bash -c 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null'
run "intel_pstate no_turbo" bash -c 'cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo n/a'
run "cpu boost"     bash -c 'cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo n/a'
run "tuned active profile"  tuned-adm active
run "tuned list"    tuned-adm list
run "power-profiles-daemon" powerprofilesctl list

# ---------------------------------------------------------------------
section "3. MEMORY"
run "free -h"       free -h
run "swap devices"  swapon --show
run "swappiness"    cat /proc/sys/vm/swappiness
run "zram"          bash -c 'zramctl 2>/dev/null || echo none'
run "transparent hugepages" cat /sys/kernel/mm/transparent_hugepage/enabled

# ---------------------------------------------------------------------
section "4. GPU AND DISPLAY"
run "GPU devices"   bash -c 'lspci -nnk | grep -EA3 -i "vga|3d controller|display"'
run "driver in use" bash -c 'lspci -k | grep -EA3 -i "vga|3d|display" | grep -i "driver in use"'
run "nvidia-smi"    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
run "glxinfo renderer" bash -c 'glxinfo -B 2>/dev/null | grep -E "renderer|version" || echo "glxinfo not installed"'
run "vulkan devices" bash -c 'vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName" || echo "vulkaninfo not installed"'
run "monitors"      bash -c 'xrandr --query 2>/dev/null | grep -E " connected" || echo "xrandr not available"'
run "ubuntu-drivers devices" ubuntu-drivers devices

# ---------------------------------------------------------------------
section "5. STORAGE"
run "lsblk"         lsblk -o NAME,SIZE,TYPE,ROTA,DISC-GRAN,FSTYPE,MOUNTPOINT,MODEL
run "df"            df -hT -x tmpfs -x devtmpfs -x squashfs
run "fstab"         cat /etc/fstab
run "fstrim timer"  systemctl is-enabled fstrim.timer
run "smart (if available)" bash -c 'for d in /dev/sd? /dev/nvme?n1; do [ -e "$d" ] && echo "$d: $(sudo -n smartctl -H "$d" 2>/dev/null | grep -i "overall\|result" || echo "need sudo/smartctl")"; done'

# ---------------------------------------------------------------------
section "6. POWER, SENSORS, BATTERY"
run "battery"       bash -c 'ls /sys/class/power_supply/ 2>/dev/null; for b in /sys/class/power_supply/BAT*; do [ -d "$b" ] && echo "$b capacity=$(cat $b/capacity 2>/dev/null)% status=$(cat $b/status 2>/dev/null)"; done'
run "sensors"       bash -c 'sensors 2>/dev/null | head -60 || echo "lm-sensors not available"'
run "thermal zones" bash -c 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type 2>/dev/null): $(cat $z/temp 2>/dev/null)"; done'

# ---------------------------------------------------------------------
section "7. NETWORK, BLUETOOTH, AUDIO"
run "network devices" nmcli device status
run "wifi/eth pci"  bash -c 'lspci | grep -Ei "network|ethernet|wireless"'
run "bluetooth"     bash -c 'systemctl is-active bluetooth; bluetoothctl devices 2>/dev/null || echo "bluetoothctl not available"'
run "audio server"  bash -c 'pactl info 2>/dev/null | grep -E "Server Name|Default Sink" || echo "pactl not available"'
run "audio devices" bash -c 'pactl list short sinks 2>/dev/null'

# ---------------------------------------------------------------------
section "8. KERNEL, BOOT, SERVICES, FIREWALL"
run "kernel cmdline" cat /proc/cmdline
run "grub defaults" bash -c 'grep -E "^GRUB_(CMDLINE|DEFAULT|TIMEOUT)" /etc/default/grub'
run "installed kernels" bash -c 'dpkg -l | grep -E "linux-image-[0-9]" | awk "{print \$2, \$3}"'
run "ufw status"    bash -c 'sudo -n ufw status verbose 2>/dev/null || echo "run: sudo ufw status verbose"'
dump_to "enabled-services.txt" systemctl list-unit-files --state=enabled --no-pager
dump_to "running-services.txt" systemctl list-units --type=service --state=running --no-pager
dump_to "timers.txt" systemctl list-timers --all --no-pager
run "crontab"       bash -c 'crontab -l 2>/dev/null || echo "no user crontab"'
run "sysctl (current, selected)" bash -c 'sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.vfs_cache_pressure net.core.rmem_max net.ipv4.tcp_congestion_control 2>/dev/null'
run "journal size"  journalctl --disk-usage

# ---------------------------------------------------------------------
section "9. PACKAGES (apt)"
dump_to "apt-manual.txt"      bash -c "apt-mark showmanual | sort"
dump_to "apt-all-installed.txt" bash -c "dpkg-query -W -f='\${Package}\t\${Version}\n' | sort"
dump_to "apt-upgradable.txt"  bash -c "apt list --upgradable 2>/dev/null"
dump_to "apt-sources.txt"     bash -c "cat /etc/apt/sources.list 2>/dev/null; grep -rh '^deb\|^Types' /etc/apt/sources.list.d/ 2>/dev/null"
dump_to "apt-held.txt"        apt-mark showhold
run "manual package count" bash -c "apt-mark showmanual | wc -l"

# ---------------------------------------------------------------------
section "10. FLATPAK, SNAP, OTHER PACKAGE MANAGERS"
if have flatpak; then
    dump_to "flatpak-apps.txt"   flatpak list --app --columns=application,name,version,origin
    dump_to "flatpak-runtimes.txt" flatpak list --runtime --columns=application,version,origin
    run "flatpak remotes" flatpak remotes
    run "flatpak overrides" bash -c 'ls ~/.local/share/flatpak/overrides 2>/dev/null || echo none'
else
    echo "flatpak not installed" >> "$LOG"
fi
if have snap; then dump_to "snap-list.txt" snap list; else echo "snap not installed" >> "$LOG"; fi
dump_to "npm-global.txt"   bash -c "npm ls -g --depth=0 2>/dev/null"
dump_to "pip-user.txt"     bash -c "python3 -m pip list --user 2>/dev/null"
run "cargo installs" bash -c 'ls ~/.cargo/bin 2>/dev/null || echo none'
run "pipx"          bash -c 'pipx list 2>/dev/null | head -40 || echo "pipx not installed"'

# ---------------------------------------------------------------------
section "11. CINNAMON DESKTOP: THEME, FONTS, WALLPAPER, PANELS"
dump_to "dconf-full.ini" dconf dump /
dump_to "cinnamon-settings.ini" dconf dump /org/cinnamon/
dump_to "gnome-desktop-settings.ini" dconf dump /org/gnome/desktop/
dump_to "keybindings-media-wm.ini" bash -c 'dconf dump /org/gnome/settings-daemon/plugins/media-keys/; dconf dump /org/cinnamon/desktop/keybindings/; dconf dump /org/cinnamon/desktop/wm/keybindings/'
run "gtk theme"     gsettings get org.cinnamon.desktop.interface gtk-theme
run "icon theme"    gsettings get org.cinnamon.desktop.interface icon-theme
run "cursor theme"  gsettings get org.cinnamon.desktop.interface cursor-theme
run "cinnamon theme" gsettings get org.cinnamon.theme name
run "window manager theme" gsettings get org.cinnamon.desktop.wm.preferences theme
run "font"          gsettings get org.cinnamon.desktop.interface font-name
run "monospace font" gsettings get org.cinnamon.desktop.interface monospace-font-name
run "text scaling"  gsettings get org.cinnamon.desktop.interface text-scaling-factor
run "wallpaper"     gsettings get org.cinnamon.desktop.background picture-uri
run "color scheme"  gsettings get org.cinnamon.desktop.interface color-scheme
run "enabled applets (panel)" gsettings get org.cinnamon enabled-applets
run "enabled desklets" gsettings get org.cinnamon enabled-desklets
run "enabled extensions" gsettings get org.cinnamon enabled-extensions
run "startup programs (dconf)" dconf read /org/cinnamon/startup-programs
run "custom keybindings list" gsettings get org.cinnamon.desktop.keybindings custom-list
run "default apps (mime)" bash -c 'for m in text/html x-scheme-handler/http video/mp4 audio/mpeg image/png application/pdf; do echo "$m -> $(xdg-mime query default $m)"; done'

# ---------------------------------------------------------------------
section "12. INSTALLED APPLETS, DESKLETS, THEMES, ICONS, FONTS"
for d in applets desklets extensions; do
    run "~/.local/share/cinnamon/$d" bash -c "ls -la ~/.local/share/cinnamon/$d 2>/dev/null || echo none"
done
run "applet metadata" bash -c 'for m in ~/.local/share/cinnamon/applets/*/metadata.json; do [ -f "$m" ] && echo "$m: $(grep -o "\"name\": *\"[^\"]*\"" "$m" | head -1)"; done'
run "system applets" bash -c 'ls /usr/share/cinnamon/applets 2>/dev/null | head -80'
run "themes (user)" bash -c 'ls ~/.themes ~/.local/share/themes 2>/dev/null || echo none'
run "icons (user)"  bash -c 'ls ~/.icons ~/.local/share/icons 2>/dev/null || echo none'
run "fonts (user)"  bash -c 'ls ~/.fonts ~/.local/share/fonts 2>/dev/null || echo none'
run "cinnamon spices config" bash -c 'ls ~/.cinnamon/configs 2>/dev/null | head -80 || echo none'

# ---------------------------------------------------------------------
section "13. AUTOSTART, STARTUP, SHORTCUTS, SHELL"
run "autostart entries" bash -c 'for f in ~/.config/autostart/*.desktop; do [ -f "$f" ] && echo "$(basename "$f"): $(grep -E "^(Exec|Hidden|X-GNOME-Autostart-enabled)=" "$f" | tr "\n" " ")"; done'
run "custom keybinding entries" bash -c 'dconf dump /org/cinnamon/desktop/keybindings/ | head -80'
run "bash aliases"   bash -c 'grep -hE "^\s*alias " ~/.bashrc ~/.bash_aliases 2>/dev/null || echo none'
run "PATH"           bash -c 'echo "$PATH" | tr ":" "\n"'
dump_to "bashrc-tail.txt" bash -c 'tail -n 80 ~/.bashrc'

# ---------------------------------------------------------------------
section "14. DEVELOPMENT / USER-LEVEL TOOLS"
run "versions" bash -c 'for c in git python3 node npm java gcc code google-chrome flatpak docker virtualbox; do printf "%-14s %s\n" "$c" "$(command -v $c >/dev/null && ($c --version 2>/dev/null | head -1) || echo NOT INSTALLED)"; done'
run "git identity presence" bash -c 'git config --global user.name >/dev/null && echo "user.name set" || echo "user.name not set"'
run "docker group"  bash -c 'id -nG | tr " " "\n" | grep -E "docker|vboxusers|sambashare|dialout" || echo "none of docker/vboxusers/sambashare/dialout"'
run "samba shares"  bash -c 'testparm -s 2>/dev/null | grep "^\[" || echo "no samba config or testparm missing"'

# ---------------------------------------------------------------------
section "15. DISK USAGE OF BIG FOLDERS"
run "home sizes"    bash -c 'du -sh ~/.cache ~/.local ~/.config ~/Downloads ~/Documents ~/Pictures ~/Videos ~/Music 2>/dev/null'

echo
echo "Done. Log: $LOG"
echo "Copy this folder to share it:  $OUT"
