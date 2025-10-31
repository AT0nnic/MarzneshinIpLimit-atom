#!/usr/bin/env bash
set -e

APP_NAME="marzneshiniplimit"
CONFIG_DIR="/opt/$APP_NAME"
COMPOSE_FILE="$CONFIG_DIR/docker-compose.yml"
REPO_URL="https://raw.githubusercontent.com/AT0nnic/MarzneshinIpLimit-atom/main"

colorized_echo() {
    local color=$1; shift
    local text=$@
    case $color in
        red) echo -e "\e[91m${text}\e[0m" ;;
        green) echo -e "\e[92m${text}\e[0m" ;;
        yellow) echo -e "\e[93m${text}\e[0m" ;;
        blue) echo -e "\e[94m${text}\e[0m" ;;
        *) echo "${text}" ;;
    esac
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "Please run as root (use sudo)"
        exit 1
    fi
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        colorized_echo blue "Installing Docker..."
        curl -fsSL https://get.docker.com | bash
    fi
}

install_compose() {
    if ! docker compose version >/dev/null 2>&1; then
        colorized_echo blue "Installing Docker Compose plugin..."
        apt-get update -y && apt-get install -y docker-compose-plugin
    fi
}

setup_files() {
    mkdir -p "$CONFIG_DIR"
    curl -sL "$REPO_URL/docker-compose.yml" -o "$COMPOSE_FILE"
    curl -sL "https://raw.githubusercontent.com/muttehitler/MarzneshinIpLimit/main/config.json.example" -o "$CONFIG_DIR/config.json"
    touch "$CONFIG_DIR/app.log"
    colorized_echo green "✅ Configuration and compose files are ready"
}

install_services() {
    cd "$CONFIG_DIR"
    docker compose down || true
    docker compose pull
    docker compose up -d
    colorized_echo green "✅ Services are up!"
    colorized_echo yellow "Web UI → http://YOUR_SERVER_IP:8080"
}

uninstall_all() {
    docker compose -f "$COMPOSE_FILE" down || true
    rm -rf "$CONFIG_DIR"
    colorized_echo green "✅ Everything removed successfully."
}

case "$1" in
    install)
        check_root
        install_docker
        install_compose
        setup_files
        install_services
        ;;
    uninstall)
        uninstall_all
        ;;
    *)
        echo "Usage: $0 [install|uninstall]"
        ;;
esac
