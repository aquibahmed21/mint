#!/usr/bin/env bash
# =====================================================================
#  OPTIONAL extras. Each item asks first, and the default is NO.
#  These are the personal or risky items that were removed from the
#  main scripts. Nothing here runs unless you answer y.
#      bash 03-optional-extras.sh
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PERSONAL_TABS=(
    https://accounts.google.com/ServiceLogin
    https://github.com/login
    https://chatgpt.com
    https://saarathy.in:3000/
    https://aahlaad.in:2000/
    https://dev.aahlaad.in:2200/
    https://windsurf.com/account/login
)

wipe_browser_profiles() {
    echo "This deletes Firefox and Chromium profiles, bookmarks and logins."
    read -rp "Type 'yes' to continue: " ans
    [[ $ans == "yes" ]] || { echo "Cancelled."; return 0; }
    rm -rf ~/.mozilla ~/.config/chromium ~/.cache/chromium
    sudo rm -rf /etc/chromium
}

open_personal_tabs() {
    google-chrome "${PERSONAL_TABS[@]}" >/dev/null 2>&1 &
}

work_launcher() {
    code >/dev/null 2>&1 &
    google-chrome >/dev/null 2>&1 &
    sticky >/dev/null 2>&1 &
    sleep 3
    (cd "$HOME/Documents/Aahlaad/Worksnaps/bin" && sh ./run.sh)
}

saarathy_checkout() {
    # Username and password are typed at the prompt. Nothing is saved in this file.
    local user pass dest="$HOME/Documents/Aahlaad"
    read -rp "SVN username: " user
    read -rsp "SVN password: " pass; echo
    mkdir -p "$dest" && cd "$dest" || return 1
    svn checkout --username "$user" --password "$pass" \
        https://dev.aahlaad.com:8443/svn/SaarathyGUI/ .
}

full_dconf_restore() {
    local file="$BUNDLE_DIR/dconf/dconf-full.ini"
    [[ -f $file ]] || { echo "No $file. Run 00-export-from-old-pc.sh first."; return 1; }
    echo "This overwrites ALL dconf settings with your old PC's settings."
    read -rp "Type 'yes' to continue: " ans
    [[ $ans == "yes" ]] || { echo "Cancelled."; return 0; }
    dconf load / < "$file"
}

open_startup_settings() {
    cinnamon-settings startup >/dev/null 2>&1 &
}

remove_mint_extras() {
    # mintdrivers and mintlocale can break driver and language tools.
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove \
        mintbackup gucharmap simple-scan mintdrivers mintlocale
}

main() {
    init_run 03-optional-extras

    ask_yes "1. Delete old Firefox/Chromium profiles and caches?" \
        && run_step "Wipe browser profiles" wipe_browser_profiles

    ask_yes "2. Open your personal login tabs in Chrome?" \
        && run_step "Open personal tabs" open_personal_tabs

    ask_yes "3. Start the Worksnaps work launcher (VS Code, Chrome, Sticky, run.sh)?" \
        && run_step "Work launcher" work_launcher

    ask_yes "4. Check out the SaarathyGUI project with SVN?" \
        && run_step "SaarathyGUI SVN checkout" saarathy_checkout

    ask_yes "5. Restore your FULL dconf settings from the bundle (overwrites everything)?" \
        && run_step "Full dconf restore" full_dconf_restore

    ask_yes "6. Open Cinnamon startup-programs settings?" \
        && run_step "Startup settings" open_startup_settings

    ask_yes "7. Remove Mint extras (mintbackup, gucharmap, simple-scan, mintdrivers, mintlocale)?" \
        && run_step "Remove Mint extras" remove_mint_extras

    print_summary
}

main "$@"
