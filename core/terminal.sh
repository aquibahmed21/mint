#!/usr/bin/env bash
# =====================================================================
#  TERMINAL - Terminator plus the custom prompt (user, host, short path)
#  REQUIRED: run by 01-base-install.sh
#
#    bash core/terminal.sh install   Install Terminator and fonts, add the prompt to ~/.bashrc
#    bash core/terminal.sh status    Show whether the prompt block is in place
#    bash core/terminal.sh purge     Remove the prompt block (and Terminator, if you agree)
#
#  The prompt is written between two marker lines in ~/.bashrc, so it
#  can be removed later without touching anything else.
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "terminal-$ACTION"

PROMPT_FILE="$SCRIPT_DIR/core/terminatorUI.txt"
RC="$HOME/.bashrc"
BEGIN="# >>> mint-setup prompt >>>"
END="# <<< mint-setup prompt <<<"

block_present() {
    grep -qF "$BEGIN" "$RC" 2>/dev/null
}

install_terminal() {
    install_packages terminator fonts-powerline || return 1
    [[ -f $PROMPT_FILE ]] || { echo "Missing $PROMPT_FILE"; return 1; }

    if block_present; then
        echo "Prompt block already in $RC. Not added twice."
    else
        {
            echo ""
            echo "$BEGIN"
            cat "$PROMPT_FILE"
            echo "$END"
        } >> "$RC" || return 1
        echo "Prompt added to $RC."
    fi
    record addon terminal
    echo "Open a new terminal window to see the prompt."
}

status_terminal() {
    if block_present; then echo "Prompt block: in $RC"; else echo "Prompt block: NOT in $RC"; fi
    if have terminator; then echo "Terminator: installed"; else echo "Terminator: not installed"; fi
    if dpkg -s fonts-powerline >/dev/null 2>&1; then echo "Powerline fonts: installed"; else echo "Powerline fonts: not installed"; fi
}

purge_terminal() {
    echo "This removes the prompt block from $RC and uninstalls Terminator."
    ask_yes "Continue?" || { echo "Cancelled."; return 0; }

    if block_present; then
        cp "$RC" "$RC.bak-$(date +%F_%H%M%S)"
        sed -i "/^$(printf '%s' "$BEGIN" | sed 's/[][\.*^$/]/\\&/g')\$/,/^$(printf '%s' "$END" | sed 's/[][\.*^$/]/\\&/g')\$/d" "$RC"
        echo "Prompt block removed. A backup of .bashrc was saved next to it."
    fi
    if ask_yes "Also uninstall Terminator?"; then
        apt_remove terminator
    fi
    unrecord addon terminal
}

case "$ACTION" in
    install) run_step "Terminal and prompt" install_terminal ;;
    status)  status_terminal ;;
    purge)   run_step "Remove terminal prompt" purge_terminal ;;
    *)       echo "Usage: bash core/terminal.sh install|status|purge"; exit 1 ;;
esac

print_summary
