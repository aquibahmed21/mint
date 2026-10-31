#!/usr/bin/env bash
# =====================================================================
#  FTP SERVER - vsftpd with encrypted logins (FTPS)
#
#    bash optional/ftp.sh install   Install vsftpd, create FTP users, open the firewall
#    bash optional/ftp.sh status    Show service, port, firewall rules and users
#    bash optional/ftp.sh purge     Remove vsftpd, firewall rules and (asked) users/files
#
#  Security defaults:
#    - Anonymous login OFF
#    - Only users listed in /etc/vsftpd.userlist can log in
#    - Each user is locked inside their own folder (chroot)
#    - TLS ON: plain-text logins are refused. Clients must use
#      "explicit FTP over TLS" (FileZilla: Encryption = Require explicit FTP over TLS).
#      The certificate is self-signed, so the client will warn once. Accept it.
#      Set FTP_TLS=0 below only on a trusted local network.
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

ACTION="${1:-status}"
init_run "ftp-$ACTION"

FTP_TLS=1                     # 1 = encrypted (recommended). 0 = plain FTP (not recommended).
PASV_MIN=40000                # passive data ports for file transfers
PASV_MAX=40100
FTP_ROOT=/srv/ftp             # each user gets /srv/ftp/<username>
CONF=/etc/vsftpd.conf
USERLIST=/etc/vsftpd.userlist
CERT=/etc/ssl/private/vsftpd.pem
NOLOGIN=/usr/sbin/nologin

write_config() {
    local tls_block=""
    if (( FTP_TLS )); then
        tls_block="ssl_enable=YES
rsa_cert_file=$CERT
rsa_private_key_file=$CERT
allow_anon_ssl=NO
force_local_logins_ssl=YES
force_local_data_ssl=YES
ssl_tlsv1=NO
ssl_sslv2=NO
ssl_sslv3=NO
ssl_tlsv1_2=YES"
    else
        tls_block="ssl_enable=NO"
    fi

    sudo tee "$CONF" >/dev/null <<EOF
# Written by mint-setup/optional/ftp.sh
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
userlist_enable=YES
userlist_file=$USERLIST
userlist_deny=NO
pasv_enable=YES
pasv_min_port=$PASV_MIN
pasv_max_port=$PASV_MAX
$tls_block
EOF
}

make_certificate() {
    if [[ -f $CERT ]]; then
        echo "Certificate already exists: $CERT"
        return 0
    fi
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -subj "/CN=$(hostname)" -keyout "$CERT" -out "$CERT" || return 1
    sudo chmod 600 "$CERT"
}

add_ftp_user() {
    local user pass pass2 reply
    read -rp "FTP username [ftpuser]: " user
    user=${user:-ftpuser}
    if [[ ! $user =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; then
        echo "Invalid name. Use lowercase letters, digits, - or _ (start with a letter)."
        return 1
    fi

    if ! id "$user" >/dev/null 2>&1; then
        sudo mkdir -p "$FTP_ROOT"
        # The user's home is their FTP folder. No shell, so they cannot log in to the desktop.
        grep -qxF "$NOLOGIN" /etc/shells || echo "$NOLOGIN" | sudo tee -a /etc/shells >/dev/null
        sudo useradd --home-dir "$FTP_ROOT/$user" --create-home --shell "$NOLOGIN" "$user" || return 1
    else
        echo "User $user already exists. Keeping it and only updating the password."
    fi

    read -rsp "Password for $user (typed hidden): " pass; echo
    read -rsp "Type it again: " pass2; echo
    if [[ -z $pass || $pass != "$pass2" ]]; then
        echo "Passwords are empty or do not match. User not changed."
        return 1
    fi
    printf '%s:%s\n' "$user" "$pass" | sudo chpasswd || return 1

    if ! grep -qxF "$user" "$USERLIST" 2>/dev/null; then
        echo "$user" | sudo tee -a "$USERLIST" >/dev/null
    fi
    echo "User $user can log in and sees only: $FTP_ROOT/$user"
}

open_firewall() {
    if have ufw; then
        sudo ufw allow 21/tcp comment 'FTP control' >/dev/null || return 1
        sudo ufw allow "$PASV_MIN:$PASV_MAX/tcp" comment 'FTP passive data' >/dev/null || return 1
        echo "Firewall: port 21 and $PASV_MIN-$PASV_MAX opened."
    else
        echo "ufw not found. Open ports 21 and $PASV_MIN-$PASV_MAX yourself."
    fi
}

install_ftp() {
    apt_install vsftpd || return 1

    [[ -f $CONF ]] && sudo cp "$CONF" "$CONF.bak-$(date +%F_%H%M%S)"
    write_config || return 1
    sudo touch "$USERLIST"
    sudo chmod 600 "$USERLIST"

    if (( FTP_TLS )); then
        make_certificate || return 1
    fi

    open_firewall || return 1

    sudo systemctl enable vsftpd || return 1
    sudo systemctl restart vsftpd || return 1

    local reply
    read -rp "Add an FTP user now? [Y/n] " reply
    if [[ -z $reply || $reply =~ ^[Yy]$ ]]; then
        while add_ftp_user; do
            read -rp "Add another user? [y/N] " reply
            [[ $reply =~ ^[Yy]$ ]] || break
        done
    fi

    echo
    echo "Connect from another PC (FileZilla or any FTP client):"
    echo "  Server:   $(hostname -I 2>/dev/null | awk '{print $1}')   (or this PC's address)"
    echo "  Port:     21"
    if (( FTP_TLS )); then
        echo "  Encryption: Require explicit FTP over TLS  (accept the self-signed certificate once)"
    else
        echo "  Encryption: none (plain FTP, not recommended)"
    fi
    echo "  User:     the username you created above"
    record addon ftp
}

status_ftp() {
    echo "Service: $(systemctl is-active vsftpd 2>/dev/null)"
    if ss -ltn 2>/dev/null | grep -q ':21 '; then
        echo "Port 21: listening"
    else
        echo "Port 21: not listening"
    fi
    if have ufw; then
        echo "Firewall rules:"
        sudo ufw status 2>/dev/null | grep -E "21/tcp|$PASV_MIN" || echo "  (none found)"
    fi
    echo "Users allowed to log in:"
    if [[ -s $USERLIST ]]; then sed 's/^/  /' "$USERLIST"; else echo "  (none)"; fi
    if [[ -f $CONF ]] && grep -q '^ssl_enable=YES' "$CONF"; then
        echo "Encryption: TLS on (encrypted)"
    else
        echo "Encryption: OFF (plain FTP)"
    fi
}

purge_ftp() {
    echo "This removes the FTP server, its config, certificate and firewall rules."
    ask_yes "Continue?" || { echo "Cancelled."; return 0; }

    local users=()
    if [[ -s $USERLIST ]]; then mapfile -t users < "$USERLIST"; fi

    sudo systemctl disable --now vsftpd 2>/dev/null
    apt_remove vsftpd || return 1

    if have ufw; then
        sudo ufw delete allow 21/tcp >/dev/null 2>&1
        sudo ufw delete allow "$PASV_MIN:$PASV_MAX/tcp" >/dev/null 2>&1
    fi
    sudo rm -f "$USERLIST" "$CERT"
    unrecord addon ftp

    local u
    for u in "${users[@]}"; do
        [[ -n $u ]] || continue
        if ask_yes "Delete FTP user '$u' AND their files in $FTP_ROOT/$u? (files cannot be recovered)"; then
            sudo userdel -r "$u" 2>/dev/null || sudo userdel "$u"
        else
            echo "Kept user $u and its files."
        fi
    done
    echo "FTP server removed."
}

case "$ACTION" in
    install) run_step "Install FTP server" install_ftp ;;
    status)  status_ftp ;;
    purge)   run_step "Purge FTP server" purge_ftp ;;
    *)       echo "Usage: bash optional/ftp.sh install|status|purge"; exit 1 ;;
esac

print_summary
