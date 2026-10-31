#!/usr/bin/env bash
# =====================================================================
#  OPTIONAL 08 - find unused desktop items and move them out of the way
#
#  Checks: applets, extensions, desklets, themes, icons, fonts
#    - applet / extension / desklet: not placed on a panel or not enabled
#    - theme / icon: not the one Cinnamon uses
#    - font: its family is not used by any setting or any installed
#      applet / extension / desklet. Exact duplicate files are listed too.
#
#  NOTHING IS DELETED. You pick the numbers, and each item is MOVED to a
#  quarantine folder. The moves are logged, so you can move them back.
#
#    bash 08-optional-clean-unused-items.sh             this PC (live)
#    bash 08-optional-clean-unused-items.sh --bundle    mint-bundle/ (run before 00 export)
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
init_run 08-optional-clean-unused-items

MODE=live
[[ ${1:-} == "--bundle" ]] && MODE=bundle
TS=$(date +%F_%H%M%S)

if [[ $MODE == live ]]; then
    CIN_DIR="$HOME/.local/share/cinnamon"
    THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes")
    ICON_DIRS=("$HOME/.icons" "$HOME/.local/share/icons")
    FONT_DIRS=("$HOME/.fonts" "$HOME/.local/share/fonts")
    QUAR="$HOME/mint-cleanup-quarantine/$TS"
else
    CIN_DIR="$BUNDLE_DIR/cinnamon"
    THEME_DIRS=("$BUNDLE_DIR/themes")
    ICON_DIRS=("$BUNDLE_DIR/icons")
    FONT_DIRS=("$BUNDLE_DIR/fonts")
    QUAR="$SCRIPT_DIR/quarantine/bundle-$TS"
fi

# Candidate list (parallel arrays)
CAND_CAT=()
CAND_PATH=()
CAND_WHY=()
add_candidate() {   # add_candidate <category> <path> <reason>
    CAND_CAT+=("$1")
    CAND_PATH+=("$2")
    CAND_WHY+=("$3")
}

# ---------------------------------------------------------------------
#  SETTINGS
#  Live: gsettings (returns defaults too). Bundle: the exported dconf file.
# ---------------------------------------------------------------------
setting() {   # setting <schema> <bundle section> <key>
    local schema="$1" section="$2" key="$3"
    if [[ $MODE == live ]]; then
        gsettings get "$schema" "$key" 2>/dev/null
    else
        awk -v s="${section:-/}" -v k="$key" '
            BEGIN { f = (s == "") }
            /^\[.*\]$/ { f = ("[" s "]" == $0); next }
            f && index($0, k "=") == 1 { sub("^" k "=", ""); print; exit }
        ' "$BUNDLE_DIR/dconf/cinnamon.ini"
    fi
}

quoted_items() { grep -o "'[^']*'" | tr -d "'"; }   # "['a', 'b']" -> one per line
unquoted()     { tr -d "'"; }                        # "'Mint-Y'" -> Mint-Y

scan() {
    local enabled_applets enabled_ext enabled_desk
    enabled_applets=$(setting org.cinnamon "" enabled-applets | quoted_items | cut -d: -f4 | sort -u)
    enabled_ext=$(setting org.cinnamon "" enabled-extensions | quoted_items | sort -u)
    enabled_desk=$(setting org.cinnamon "" enabled-desklets | quoted_items | cut -d: -f1 | sort -u)

    # Safety: if the settings cannot be read, stop. Otherwise every item looks unused.
    if [[ -z $enabled_applets && -z $enabled_ext ]]; then
        echo "Could not read Cinnamon settings. Nothing was checked."
        return 1
    fi

    local theme_refs icon_refs font_refs
    theme_refs=$( {
        setting org.cinnamon.desktop.interface "desktop/interface" gtk-theme | unquoted
        setting org.cinnamon.theme "theme" name | unquoted
        setting org.cinnamon.desktop.wm.preferences "desktop/wm/preferences" theme | unquoted
    } | sort -u)
    icon_refs=$( {
        setting org.cinnamon.desktop.interface "desktop/interface" icon-theme | unquoted
        setting org.cinnamon.desktop.interface "desktop/interface" cursor-theme | unquoted
        echo "default"; echo "hicolor"
    } | sort -u)

    # Applets
    local d u
    for d in "$CIN_DIR"/applets/*/; do
        [[ -d $d ]] || continue
        d=${d%/}; u=$(basename "$d")
        grep -qxF "$u" <<< "$enabled_applets" || add_candidate applet "$d" "not placed on any panel"
    done

    # Extensions
    for d in "$CIN_DIR"/extensions/*/; do
        [[ -d $d ]] || continue
        d=${d%/}; u=$(basename "$d")
        grep -qxF "$u" <<< "$enabled_ext" || add_candidate extension "$d" "not enabled"
    done

    # Desklets
    for d in "$CIN_DIR"/desklets/*/; do
        [[ -d $d ]] || continue
        d=${d%/}; u=$(basename "$d")
        grep -qxF "$u" <<< "$enabled_desk" || add_candidate desklet "$d" "not on the desktop"
    done

    # Themes (GTK, Cinnamon, window borders)
    local tdir t
    for tdir in "${THEME_DIRS[@]}"; do
        for t in "$tdir"/*/; do
            [[ -d $t ]] || continue
            t=${t%/}; u=$(basename "$t")
            grep -qxF "$u" <<< "$theme_refs" || add_candidate theme "$t" "not used by GTK, Cinnamon or window theme"
        done
    done

    # Icon and cursor themes
    local idir i
    for idir in "${ICON_DIRS[@]}"; do
        for i in "$idir"/*/; do
            [[ -d $i ]] || continue
            i=${i%/}; u=$(basename "$i")
            grep -qxF "$u" <<< "$icon_refs" || add_candidate icon "$i" "not the active icon or cursor theme"
        done
    done

    # Fonts: text that counts as "in use" = all dconf settings + all applet/extension/desklet files
    local used_text
    used_text=$(mktemp) || return 1
    if [[ $MODE == live ]]; then
        dconf dump / 2>/dev/null
        gsettings get org.gnome.desktop.interface font-name 2>/dev/null
        gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null
        gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null
        gsettings get org.cinnamon.desktop.interface font-name 2>/dev/null
        gsettings get org.cinnamon.desktop.interface document-font-name 2>/dev/null
    else
        cat "$BUNDLE_DIR/dconf/dconf-full.ini" 2>/dev/null
    fi > "$used_text"
    grep -rhI . "$CIN_DIR/applets" "$CIN_DIR/extensions" "$CIN_DIR/desklets" 2>/dev/null >> "$used_text"

    # Duplicate font files (same bytes): keep the first, list the rest
    local -A seen_hash=()
    local f h fam
    while IFS= read -r -d '' f; do
        h=$(md5sum "$f" | cut -d' ' -f1)
        if [[ -n ${seen_hash[$h]:-} ]]; then
            add_candidate font "$f" "exact duplicate of ${seen_hash[$h]##*/}"
            continue
        fi
        seen_hash[$h]=$f

        fam=$(fc-scan --format '%{family[0]}\n' "$f" 2>/dev/null | head -n1)
        [[ -z $fam ]] && fam=$(basename "$f" | sed 's/\.[^.]*$//')
        if ! grep -qiF -- "$fam" "$used_text"; then
            add_candidate font "$f" "family '$fam' not used by settings or installed applets"
        fi
    done < <(find "${FONT_DIRS[@]}" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -print0 2>/dev/null)
    rm -f "$used_text"
}

show_candidates() {
    if (( ${#CAND_PATH[@]} == 0 )); then
        echo "Nothing unused found."
        return 0
    fi
    echo
    printf ' %-4s %-10s %-44s %s\n' "#" "TYPE" "NAME" "WHY"
    local i
    for i in "${!CAND_PATH[@]}"; do
        printf ' %-4s %-10s %-44s %s\n' "$((i + 1))" "${CAND_CAT[i]}" "$(basename "${CAND_PATH[i]}")" "${CAND_WHY[i]}"
    done
}

# "1 3 5-7 all" -> one number per line
parse_selection() {
    local tok
    for tok in "$@"; do
        if [[ $tok == all ]]; then
            seq 1 "${#CAND_PATH[@]}"
        elif [[ $tok =~ ^([0-9]+)-([0-9]+)$ ]]; then
            seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        elif [[ $tok =~ ^[0-9]+$ ]]; then
            echo "$tok"
        else
            echo "Ignoring: $tok" >&2
        fi
    done
}

quarantine() {
    local sel="$1" picks=() n i dest base
    # $sel is split on purpose so each word is one selection
    # shellcheck disable=SC2086
    mapfile -t picks < <(parse_selection $sel | sort -un)
    mkdir -p "$QUAR" || return 1
    : > "$QUAR/moved.tsv"
    for n in "${picks[@]}"; do
        (( n >= 1 && n <= ${#CAND_PATH[@]} )) || continue
        i=$((n - 1))
        dest="$QUAR/${CAND_CAT[i]}"
        base=$(basename "${CAND_PATH[i]}")
        mkdir -p "$dest"
        if mv -- "${CAND_PATH[i]}" "$dest/$n-$base"; then
            printf '%s\t%s\n' "${CAND_PATH[i]}" "$dest/$n-$base" >> "$QUAR/moved.tsv"
            echo "moved: ${CAND_PATH[i]}"
        else
            echo "could not move: ${CAND_PATH[i]}"
        fi
    done
    echo
    echo "Moved items are in: $QUAR"
    echo "To put one back: mv '<quarantine path>' '<original path>'  (see moved.tsv)"
}

main() {
    echo "Mode: $MODE"
    echo "Checking applets, extensions, desklets, themes, icons and fonts..."
    scan || return 1
    show_candidates
    (( ${#CAND_PATH[@]} == 0 )) && return 0

    echo
    read -rp "Numbers to move to quarantine (e.g. 1 3 5-7, or 'all'; Enter to skip): " sel
    [[ -z $sel ]] && { echo "Nothing moved."; return 0; }
    run_step "Move selected items to quarantine" quarantine "$sel"
    print_summary
}

main
