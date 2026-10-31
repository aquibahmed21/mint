#!/usr/bin/env bash
# =====================================================================
#  07 - CLEAN UP: tidy Downloads, clear safe caches, check RAM.
#  Every action explains what it will do and asks first.
#
#      bash 07-cleanup-downloads-ram.sh
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
init_run 07-cleanup-downloads-ram

DL="$HOME/Downloads"

# Folder name for a file, based on its extension
category_of() {
    local ext="${1##*.}"
    ext=${ext,,}
    case $ext in
        deb|rpm|appimage|flatpakref|msi|exe|run)                 echo "Installers" ;;
        jpg|jpeg|png|gif|webp|svg|heic|bmp|tif|tiff)             echo "Pictures" ;;
        mp4|mkv|avi|mov|webm|flv|wmv|m4v)                        echo "Videos" ;;
        mp3|wav|flac|m4a|ogg|aac)                                echo "Music" ;;
        pdf|doc|docx|odt|rtf|txt|md|csv|xls|xlsx|ods|ppt|pptx|odp|epub) echo "Documents" ;;
        zip|rar|7z|tar|gz|tgz|bz2|xz)                            echo "Archives" ;;
        *)                                                       echo "Other" ;;
    esac
}

organize_downloads() {
    echo "== 1. Organize Downloads"
    [[ -d $DL ]] || { echo "No Downloads folder."; return 0; }

    local f cat item
    local plan=()
    while IFS= read -r -d '' f; do
        case $f in *.crdownload|*.part|*.tmp) continue ;; esac
        plan+=("$(category_of "$(basename "$f")")|$f")
    done < <(find "$DL" -maxdepth 1 -type f -print0)

    if (( ${#plan[@]} == 0 )); then
        echo "Downloads has no loose files. Nothing to organize."
        return 0
    fi

    echo "Loose files in Downloads, by planned folder:"
    printf '%s\n' "${plan[@]}" | cut -d'|' -f1 | sort | uniq -c | sed 's/^/  /'
    ask_yes "Move them into folders like Downloads/Documents, Downloads/Installers?" || return 0

    for item in "${plan[@]}"; do
        cat=${item%%|*}
        f=${item#*|}
        mkdir -p "$DL/$cat"
        mv -n -- "$f" "$DL/$cat/" && echo "moved $(basename "$f") -> $cat/"
    done
}

clean_downloads_junk() {
    echo
    echo "== 2. Unwanted files in Downloads"
    [[ -d $DL ]] || return 0

    local old=() inst=() empty
    mapfile -d '' -t old < <(find "$DL" -type f \( -name '*.crdownload' -o -name '*.part' -o -name '*.tmp' \) -mtime +2 -print0)
    echo "Unfinished downloads older than 2 days: ${#old[@]}"
    if (( ${#old[@]} )) && ask_yes "Delete them?"; then
        rm -f -- "${old[@]}"
    fi

    empty=$(find "$DL" -mindepth 1 -type d -empty | wc -l)
    echo "Empty folders in Downloads: $empty"
    if (( empty )) && ask_yes "Delete empty folders?"; then
        find "$DL" -mindepth 1 -type d -empty -delete
    fi

    mapfile -d '' -t inst < <(find "$DL" -type f \( -name '*.deb' -o -name '*.AppImage' -o -name '*.flatpakref' \) -mtime +30 -print0)
    echo "Installers older than 30 days: ${#inst[@]}"
    if (( ${#inst[@]} )) && ask_yes "Delete old installers? (they can be downloaded again)"; then
        rm -f -- "${inst[@]}"
    fi
}

find_duplicates() {
    echo
    echo "== 3. Duplicate files in Downloads"
    [[ -d $DL ]] || return 0

    # md5sum output is "<hash>  <path>". Keep the first file of each group, list the rest.
    local dups
    dups=$(find "$DL" -type f -exec md5sum -- {} + 2>/dev/null \
        | sort | awk '{ h = $1; f = substr($0, 35); if (h == prev) print f; prev = h }')
    if [[ -z $dups ]]; then
        echo "No duplicates found."
        return 0
    fi
    echo "Duplicate copies (the first copy of each file is kept):"
    echo "$dups" | sed 's/^/  /'
    if ask_yes "Delete these duplicate copies?"; then
        while IFS= read -r f; do
            [[ -n $f ]] && rm -f -- "$f"
        done <<< "$dups"
    fi
}

cache_sizes() {
    local d
    for d in ~/.cache/thumbnails ~/.cache/google-chrome ~/.cache/pip ~/.cache/uv ~/.cache/npm \
             ~/.var/app/org.mozilla.firefox/cache ~/.local/share/Trash; do
        [[ -d $d ]] && du -sh "$d" 2>/dev/null
    done
}

clean_caches() {
    echo
    echo "== 4. Caches and leftovers"
    echo "Current sizes:"
    cache_sizes | sed 's/^/  /'

    if ask_yes "Clear thumbnails and browser cache? (safe, rebuilt automatically)"; then
        rm -rf ~/.cache/thumbnails ~/.cache/google-chrome ~/.var/app/org.mozilla.firefox/cache
    fi
    if ask_yes "Clear pip, npm and uv download caches? (re-downloaded when needed)"; then
        python3 -m pip cache purge >/dev/null 2>&1
        have npm && npm cache clean --force >/dev/null 2>&1
        have uv && uv cache clean >/dev/null 2>&1
        rm -rf ~/.cache/pip ~/.cache/uv ~/.cache/npm
    fi
    if ask_yes "Empty the Trash? (permanently deletes trashed files)"; then
        rm -rf ~/.local/share/Trash/files/* ~/.local/share/Trash/info/*
    fi
    if ask_yes "Clean apt cache, remove unused packages, shrink system logs to 200 MB?"; then
        sudo apt-get clean
        sudo apt-get autoremove -y
        sudo journalctl --vacuum-size=200M >/dev/null 2>&1
    fi
    if have flatpak && ask_yes "Remove unused Flatpak runtimes?"; then
        sudo flatpak uninstall --unused -y
    fi

    echo "Sizes after:"
    cache_sizes | sed 's/^/  /'
}

check_ram() {
    echo
    echo "== 5. RAM"
    echo "Memory now:"
    free -h | sed 's/^/  /'
    echo
    echo "Top 10 memory users:"
    ps -eo pid,comm,%mem,rss --sort=-rss | head -n 11 | sed 's/^/  /'
    echo
    echo "Linux already uses spare RAM for caches and gives it back when apps need it."
    echo "The real gain is closing apps you don't use (see the list above)."

    if ask_yes "Flush file caches now? (safe, only frees cached data)"; then
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    fi

    local used_swap avail
    used_swap=$(free -m | awk '/^Swap:/ {print $3}')
    avail=$(free -m | awk '/^Mem:/ {print $7}')
    echo "Swap in use: ${used_swap} MB   available RAM: ${avail} MB"
    if (( used_swap > 0 && avail > used_swap + 1024 )); then
        if ask_yes "Move swapped data back into RAM now (swapoff/swapon)?"; then
            sudo swapoff -a && sudo swapon -a
        fi
    fi

    echo "Memory after:"
    free -h | sed 's/^/  /'
}

main() {
    organize_downloads
    clean_downloads_junk
    find_duplicates
    clean_caches
    check_ram
    print_summary
}

main
