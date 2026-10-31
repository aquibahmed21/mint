#!/usr/bin/env bash
# =====================================================================
#  EXPORT your current Linux Mint look and app lists into mint-bundle/
#
#  Run this on the PC you have now (not on the fresh install):
#      bash export-from-old-pc.sh
#  It only reads your settings. 02-after-reboot.sh restores the bundle later.
# =====================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$SCRIPT_DIR/mint-bundle"

if [[ -d $B ]]; then
    mv "$B" "$B.old-$(date +%F_%H%M%S)" && echo "Previous bundle moved aside."
fi
mkdir -p "$B/dconf" "$B/lists"

copy_tree() {   # copy_tree <source folder> <destination folder>
    if [[ -d $1 ]]; then
        mkdir -p "$2" && cp -a "$1/." "$2/" && echo "copied $1"
    else
        echo "skipped (missing): $1"
    fi
}

dump() {        # dump <dconf path> <file name in bundle>
    dconf dump "$1" > "$B/dconf/$2" && echo "dconf $1 -> $2"
}

echo "== Desktop settings (dconf)"
dump /org/cinnamon/ cinnamon.ini
dump /org/gnome/desktop/ gnome-desktop.ini
dump /org/gnome/settings-daemon/plugins/media-keys/ media-keys.ini
dump /org/nemo/ nemo.ini
dump /org/x/ x.ini
dump / dconf-full.ini            # everything; only used if you choose it in 03-optional-extras.sh

echo "== Applets, extensions, themes, icons, fonts"
copy_tree ~/.local/share/cinnamon/applets     "$B/cinnamon/applets"
copy_tree ~/.local/share/cinnamon/extensions  "$B/cinnamon/extensions"
copy_tree ~/.local/share/cinnamon/desklets    "$B/cinnamon/desklets"
copy_tree ~/.themes                           "$B/themes"
copy_tree ~/.local/share/themes               "$B/themes"
copy_tree ~/.icons                            "$B/icons"
copy_tree ~/.local/share/icons                "$B/icons"
copy_tree ~/.fonts                            "$B/fonts"
copy_tree ~/.local/share/fonts                "$B/fonts"

echo "== Autostart and default apps"
copy_tree ~/.config/autostart                 "$B/config/autostart"
copy_tree ~/.config/gtk-3.0                   "$B/config/gtk-3.0"
cp -f ~/.config/mimeapps.list "$B/config/" 2>/dev/null && echo "copied mimeapps.list"

echo "== Package lists (for reference)"
if command -v flatpak >/dev/null 2>&1; then
    flatpak list --app --columns=application > "$B/lists/flatpak-apps.txt" && echo "flatpak app list"
fi
apt-mark showmanual > "$B/lists/apt-manual.txt" && echo "apt manual package list"
npm ls -g --depth=0 > "$B/lists/npm-global.txt" 2>/dev/null && echo "npm global list"

cat > "$B/README.txt" <<EOF
Exported on $(date) from $(hostname).
Restored by 02-after-reboot.sh on the fresh install.
dconf/*.ini        desktop settings (dconf-full.ini is only used if you choose it in 03-optional-extras.sh)
cinnamon/          applets, extensions, desklets
themes/ icons/ fonts/   visual themes, icon sets, fonts
config/            autostart, GTK bookmarks, default apps
lists/             package lists (reference only)
EOF

echo
echo "Done. Bundle size: $(du -sh "$B" | cut -f1)"
echo "Bundle folder: $B"
