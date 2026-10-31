#!/usr/bin/env bash
# =====================================================================
#  06 - UNINSTALLER
#
#  Lists everything this kit installed (its own list, not the dependency
#  packages apt pulled in). You pick the numbers to remove.
#  The NVIDIA driver is never listed.
#
#      bash 06-uninstall-apps.sh
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
init_run 06-uninstall-apps

ENTRIES=()

# Is this entry still on the system?
entry_installed() {   # entry_installed <kind> <name>
    case $1 in
        apt)     dpkg -s "$2" >/dev/null 2>&1 ;;
        flatpak) flatpak info "$2" >/dev/null 2>&1 ;;
        npm)     npm ls -g --depth=0 "$2" >/dev/null 2>&1 ;;
        addon)
            case $2 in
                docker)     have docker ;;
                cuda)       have nvcc ;;
                virtualbox) have VBoxManage ;;
                vpn)        dpkg -s proton-vpn-gnome-desktop >/dev/null 2>&1 ;;
                ftp)        dpkg -s vsftpd >/dev/null 2>&1 ;;
                terminal)   have terminator ;;
                *)          return 1 ;;
            esac ;;
        tool)
            case $2 in
                open-webui) have docker && sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx open-webui ;;
                bun)        [[ -x $HOME/.bun/bin/bun ]] ;;
                vps-ssh)    [[ -f $HOME/.ssh/id_ed25519_vps ]] ;;
                *)          have "$2" || [[ -x $HOME/.local/bin/$2 ]] ;;
            esac ;;
        *) return 1 ;;
    esac
}

# Remove one entry, using the right uninstaller for its kind
remove_entry() {      # remove_entry <kind> <name>
    case $1 in
        apt)     apt_remove "$2" ;;
        flatpak) sudo flatpak uninstall -y "$2" && unrecord flatpak "$2" ;;
        npm)     sudo npm uninstall -g "$2" && unrecord npm "$2" ;;
        addon)   case $2 in
            ftp) bash "$SCRIPT_DIR/core/ftp.sh" purge ;;
            terminal) bash "$SCRIPT_DIR/core/terminal.sh" purge ;;
            *)   bash "$SCRIPT_DIR/optional/$2.sh" purge ;;
            esac ;;
        tool)
            case $2 in
                cloudflared|ngrok|vps-ssh) bash "$SCRIPT_DIR/05-optional-tunnels-vps.sh" remove "$2" ;;
                *)                         bash "$SCRIPT_DIR/04-optional-llm-tools.sh" remove "$2" ;;
            esac ;;
    esac
}

note_for() {
    case $1 in
        apt)     echo "system package" ;;
        flatpak) echo "Flatpak app" ;;
        npm)     echo "npm global tool" ;;
        addon)   echo "add-on (its own uninstaller)" ;;
        tool)    echo "tool" ;;
    esac
}

# Keep only entries that are still installed. Stale lines are dropped.
load_entries() {
    [[ -f $MANIFEST ]] || return 0
    local tmp kind name line
    tmp=$(mktemp) || return 1
    while IFS=$'\t' read -r kind name; do
        [[ -z $kind || -z $name ]] && continue
        if entry_installed "$kind" "$name"; then
            printf '%s\t%s\n' "$kind" "$name" >> "$tmp"
        fi
    done < <(sort -u "$MANIFEST")
    mv "$tmp" "$MANIFEST"
    while IFS= read -r line; do
        ENTRIES+=("$line")
    done < "$MANIFEST"
}

show_list() {
    echo
    printf ' %-4s %-9s %-32s %s\n' "#" "TYPE" "NAME" "NOTE"
    local i=1 line kind name
    for line in "${ENTRIES[@]}"; do
        kind=${line%%$'\t'*}
        name=${line#*$'\t'}
        printf ' %-4s %-9s %-32s %s\n' "$i" "$kind" "$name" "$(note_for "$kind")"
        i=$((i + 1))
    done
}

# "1 3 5-7 all" -> one number per line
parse_selection() {
    local tok
    for tok in "$@"; do
        if [[ $tok == all ]]; then
            seq 1 "${#ENTRIES[@]}"
        elif [[ $tok =~ ^([0-9]+)-([0-9]+)$ ]]; then
            seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        elif [[ $tok =~ ^[0-9]+$ ]]; then
            echo "$tok"
        else
            echo "Ignoring: $tok" >&2
        fi
    done
}

main() {
    echo "Reading the list of what this kit installed..."
    load_entries
    if (( ${#ENTRIES[@]} == 0 )); then
        echo "The kit has not recorded any installed items (or everything is already removed)."
        return 0
    fi

    show_list
    echo
    read -rp "Numbers to remove (e.g. 1 3 5-7, or 'all'; Enter to quit): " sel
    [[ -z $sel ]] && { echo "Nothing selected."; return 0; }

    local picks=() n line kind name
    # $sel is split on purpose so each word is one selection
    # shellcheck disable=SC2086
    mapfile -t picks < <(parse_selection $sel | sort -un)

    echo
    echo "You selected:"
    for n in "${picks[@]}"; do
        (( n >= 1 && n <= ${#ENTRIES[@]} )) && echo "  $n) ${ENTRIES[n-1]//$'\t'/  }"
    done
    echo
    ask_yes "Remove the selected items?" || { echo "Cancelled."; return 0; }

    for n in "${picks[@]}"; do
        (( n >= 1 && n <= ${#ENTRIES[@]} )) || continue
        line=${ENTRIES[n-1]}
        kind=${line%%$'\t'*}
        name=${line#*$'\t'}
        run_step "Remove $name ($kind)" remove_entry "$kind" "$name"
    done

    print_summary
    echo "Optional: remove leftover dependencies nobody needs any more with:"
    echo "    sudo apt-get autoremove"
}

main
