#!/usr/bin/env bash
# =====================================================================
#  OPTIONAL 04 - tools for web development and running LLMs locally
#
#  Menu (recommended):       bash 04-optional-llm-tools.sh
#  Command line:             bash 04-optional-llm-tools.sh status
#                            bash 04-optional-llm-tools.sh install ollama
#                            bash 04-optional-llm-tools.sh remove ollama
# =====================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
init_run 04-optional-llm-tools

ITEMS=(ollama uv nvtop webdev-apt pnpm bun flatpak-devtools open-webui)

item_label() {
    case $1 in
        ollama)           echo "Ollama" ;;
        uv)               echo "uv" ;;
        nvtop)            echo "nvtop" ;;
        webdev-apt)       echo "Web dev CLI tools" ;;
        pnpm)             echo "pnpm" ;;
        bun)              echo "Bun" ;;
        flatpak-devtools) echo "Postman + DBeaver" ;;
        open-webui)       echo "Open WebUI" ;;
    esac
}

item_desc() {
    case $1 in
        ollama)           echo "Run LLMs (Qwen, Llama, Mistral...) locally; API on localhost:11434" ;;
        uv)               echo "Very fast Python package and virtualenv manager" ;;
        nvtop)            echo "Live GPU monitor for your RTX 3060 (like htop for the GPU)" ;;
        webdev-apt)       echo "mkcert (local HTTPS), jq (JSON), httpie (API calls)" ;;
        pnpm)             echo "Fast package manager for JavaScript projects" ;;
        bun)              echo "Fast JavaScript runtime, bundler and package manager" ;;
        flatpak-devtools) echo "Postman (API testing) and DBeaver (databases), from Flathub" ;;
        open-webui)       echo "Chat web UI for local models. Needs Docker (optional/docker.sh)" ;;
    esac
}

item_check() {
    case $1 in
        ollama)           have ollama ;;
        uv)               have uv || [[ -x $HOME/.local/bin/uv ]] ;;
        nvtop)            have nvtop ;;
        webdev-apt)       have mkcert && have jq && have http ;;
        pnpm)             have pnpm ;;
        bun)              [[ -x $HOME/.bun/bin/bun ]] ;;
        flatpak-devtools) flatpak info com.getpostman.Postman >/dev/null 2>&1 \
                          && flatpak info io.dbeaver.DBeaverCommunity >/dev/null 2>&1 ;;
        open-webui)       have docker && sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx open-webui ;;
    esac
}

item_install() {
    case $1 in
        ollama)
            # Official installer from ollama.com. It asks for sudo itself and sets up a service.
            curl -fsSL https://ollama.com/install.sh | sh || return 1
            record tool ollama ;;
        uv)
            curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
            record tool uv ;;
        nvtop)
            install_packages nvtop ;;
        webdev-apt)
            install_packages mkcert libnss3-tools jq httpie ;;
        pnpm)
            sudo npm install -g pnpm || return 1
            record npm pnpm ;;
        bun)
            curl -fsSL https://bun.sh/install | bash || return 1
            record tool bun ;;
        flatpak-devtools)
            local app rc=0
            for app in com.getpostman.Postman io.dbeaver.DBeaverCommunity; do
                if sudo flatpak install -y flathub "$app"; then record flatpak "$app"; else rc=1; fi
            done
            return $rc ;;
        open-webui)
            have docker || { echo "Docker is not installed. First run: bash optional/docker.sh install"; return 1; }
            sudo docker run -d --restart unless-stopped -p 3000:8080 --name open-webui \
                ghcr.io/open-webui/open-webui:main || return 1
            echo "Open WebUI: http://localhost:3000"
            record tool open-webui ;;
    esac
}

item_remove() {
    case $1 in
        ollama)
            sudo systemctl disable --now ollama 2>/dev/null
            sudo rm -f /etc/systemd/system/ollama.service
            sudo rm -f /usr/local/bin/ollama /usr/bin/ollama
            sudo rm -rf /usr/local/lib/ollama
            sudo userdel ollama 2>/dev/null
            sudo groupdel ollama 2>/dev/null
            sudo systemctl daemon-reload
            if ask_yes "Also delete downloaded models in /usr/share/ollama? (large, cannot be undone)"; then
                sudo rm -rf /usr/share/ollama
            fi
            unrecord tool ollama ;;
        uv)
            rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
            unrecord tool uv ;;
        nvtop)
            apt_remove nvtop ;;
        webdev-apt)
            apt_remove mkcert libnss3-tools jq httpie ;;
        pnpm)
            sudo npm uninstall -g pnpm && unrecord npm pnpm ;;
        bun)
            rm -rf "$HOME/.bun"
            echo "Bun removed. Its lines in ~/.bashrc (if any) are left for you to delete."
            unrecord tool bun ;;
        flatpak-devtools)
            sudo flatpak uninstall -y com.getpostman.Postman io.dbeaver.DBeaverCommunity
            unrecord flatpak com.getpostman.Postman
            unrecord flatpak io.dbeaver.DBeaverCommunity ;;
        open-webui)
            sudo docker rm -f open-webui 2>/dev/null
            if ask_yes "Also delete the Open WebUI image?"; then
                sudo docker rmi ghcr.io/open-webui/open-webui:main
            fi
            unrecord tool open-webui ;;
    esac
}

items_cli "$@"
