#!/usr/bin/env bash
# =====================================================================
#  OPTIONAL 05 - make local servers reachable from the internet
#  (Cloudflare Tunnel and ngrok), plus SSH key for a VPS.
#
#  Neither tunnel tool needs open ports on your router. Each one makes an
#  outgoing connection to its provider, which then gives you a public address.
#
#  Menu (recommended):       bash 05-optional-tunnels-vps.sh
#  Command line:             bash 05-optional-tunnels-vps.sh status
#                            bash 05-optional-tunnels-vps.sh install ngrok
#                            bash 05-optional-tunnels-vps.sh remove ngrok
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
init_run 05-optional-tunnels-vps

ITEMS=(cloudflared ngrok vps-ssh)
VPS_KEY="$HOME/.ssh/id_ed25519_vps"

item_label() {
    case $1 in
        cloudflared) echo "Cloudflare Tunnel" ;;
        ngrok)       echo "ngrok" ;;
        vps-ssh)     echo "VPS SSH key" ;;
    esac
}

item_desc() {
    case $1 in
        cloudflared) echo "cloudflared: public https address for a local site or API (free)" ;;
        ngrok)       echo "ngrok: quick public URL for a local server (free plan, needs a token)" ;;
        vps-ssh)     echo "Creates an SSH key so you can log in to a VPS without a password" ;;
    esac
}

item_check() {
    case $1 in
        cloudflared) have cloudflared ;;
        ngrok)       have ngrok ;;
        vps-ssh)     [[ -f $VPS_KEY ]] ;;
    esac
}

item_install() {
    case $1 in
        cloudflared)
            # Cloudflare's apt repository (your PC already had this repository configured)
            sudo mkdir -p --mode=0755 /usr/share/keyrings
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
                | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null || return 1
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
                | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null || return 1
            sudo apt-get update || return 1
            install_packages cloudflared || return 1
            echo
            echo "Quick test, no account needed (Ctrl+C to stop):"
            echo "    cloudflared tunnel --url http://localhost:3000"
            echo "For a permanent named tunnel, run: cloudflared tunnel login"
            ;;
        ngrok)
            # ngrok's apt repository (check ngrok.com/docs if this stops working)
            curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
                | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null || return 1
            echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
                | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null || return 1
            sudo apt-get update || return 1
            install_packages ngrok || return 1
            local token
            read -rsp "Paste your ngrok authtoken (typed hidden, Enter to skip): " token; echo
            if [[ -n $token ]]; then
                ngrok config add-authtoken "$token"
            fi
            echo "Quick test: ngrok http 3000"
            ;;
        vps-ssh)
            mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
            if [[ -f $VPS_KEY ]]; then
                echo "Key already exists: $VPS_KEY"
            else
                ssh-keygen -t ed25519 -f "$VPS_KEY" -C "$USER@$(hostname)-vps" -N "" || return 1
            fi
            record tool vps-ssh
            echo
            echo "Copy this public key to your VPS (replace the address):"
            echo "    ssh-copy-id -i $VPS_KEY.pub user@your-vps-address"
            echo "Then log in with:  ssh -i $VPS_KEY user@your-vps-address"
            ;;
    esac
}

item_remove() {
    case $1 in
        cloudflared)
            apt_remove cloudflared
            sudo rm -f /etc/apt/sources.list.d/cloudflared.list
            if ask_yes "Also delete Cloudflare login and tunnel credentials in ~/.cloudflared?"; then
                rm -rf "$HOME/.cloudflared"
            fi ;;
        ngrok)
            apt_remove ngrok
            sudo rm -f /etc/apt/sources.list.d/ngrok.list /etc/apt/trusted.gpg.d/ngrok.asc
            if ask_yes "Also delete your ngrok authtoken config in ~/.config/ngrok?"; then
                rm -rf "$HOME/.config/ngrok"
            fi ;;
        vps-ssh)
            if ask_yes "Delete the VPS SSH key files ($VPS_KEY*)? Servers using it will lock you out."; then
                rm -f "$VPS_KEY" "$VPS_KEY.pub"
                unrecord tool vps-ssh
            fi ;;
    esac
}

items_cli "$@"
