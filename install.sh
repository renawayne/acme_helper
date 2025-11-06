#!/bin/bash

# acme_helper installer
# https://github.com/renawayne/acme_helper

set -e

# === Константы ===
export LC_ALL=C  # Fix locale warnings
INSTALL_DIR="/root/.acme_helper"
LOG_DIR="$INSTALL_DIR/logs"
CONFIG_FILE="$INSTALL_DIR/config"
ACME_HELPER_SCRIPT="$INSTALL_DIR/acme_helper.sh"
ACME_SH_DIR="/root/.acme.sh"
REPO_RAW="https://raw.githubusercontent.com/renawayne/acme_helper/main"
DATE_START=$(date +"%Y%m%d")
LOG_FILE="$LOG_DIR/log${DATE_START}.log"

# === Цвета ===
if command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
    HAS_COLOR=true
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
    HAS_COLOR=false
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

prompt_yesno() {
    local prompt_text="$1"
    local default="$2"  # y or n
    local def_text=$( [ "$default" = "y" ] && echo "y" || echo "n" )
    local input
    echo -e "${CYAN}$prompt_text [y/n] (default: $def_text): ${NC}" | tee -a "$LOG_FILE"
    read -r input
    case "${input:-$default}" in
        [Yy]* ) echo "y" ;;
        [Nn]* ) echo "n" ;;
        * ) echo "$default" ;;
    esac
}

prompt_lang() {
    local input
    echo -e "${CYAN}Выберите язык:\nru or en (default: ru): ${NC}" | tee -a "$LOG_FILE"
    read -r input
    case "${input:-ru}" in
        [Ee][Nn]*) echo "en" ;;
        *) echo "ru" ;;
    esac
}

# === Создание директорий ===
mkdir -p "$INSTALL_DIR" "$LOG_DIR"
> "$LOG_FILE"
log "${GREEN}=== Установка acme_helper ===${NC}"

# === Язык ===
LANG=$(prompt_lang)

# === Тексты (до промптов!) ===
if [ "$LANG" = "en" ]; then
    TXT_MOTD="This script will install https://github.com/renawayne/acme_helper/ via alias in .bashrc (acme_helper).\nIt simplifies work with https://github.com/acmesh-official/acme.sh.\nAdd script reminder to motd?"
    TXT_MOTD_SSL="Add existing certs reminder to motd? (searches /root/.acme.sh/*_ecc/)"
    TXT_UPGRADE="Run 'sudo apt-get update && sudo apt-get upgrade -y'?"
    TXT_DONE="Script installed. Use 'acme_helper' or press enter to run now.\nAlias in .bashrc. Press enter: reloads bash, shows motd, runs via alias.\nIf not started: check /root/.acme_helper/acme_helper.sh\nacme.sh in /root/.acme.sh/acme.sh"
else
    TXT_MOTD="Этот скрипт установит https://github.com/renawayne/acme_helper/ через alias в .bashrc (acme_helper).\nУпрощает работу с https://github.com/acmesh-official/acme.sh.\nДобавить напоминание о скрипте в motd?"
    TXT_MOTD_SSL="Добавить напоминание о сертификатах в motd? (ищет /root/.acme.sh/*_ecc/)"
    TXT_UPGRADE="Выполнить 'sudo apt-get update && sudo apt-get upgrade -y'?"
    TXT_DONE="Скрипт установлен. Используйте 'acme_helper' или enter для запуска.\nАлиас в .bashrc. Enter: перезагрузка bash, motd и запуск.\nЕсли не запустился: /root/.acme_helper/acme_helper.sh\nacme.sh в /root/.acme.sh/acme.sh"
fi

# === Вопросы ===
MOTD_CHOICE=$(prompt_yesno "$TXT_MOTD" "y")
MOTD_SSL_CHOICE=$(prompt_yesno "$TXT_MOTD_SSL" "y")
UPGRADE_CHOICE=$(prompt_yesno "$TXT_UPGRADE" "y")

# === Конфиг (безопасно) ===
mkdir -p "$INSTALL_DIR"
cat > "$CONFIG_FILE" <<EOF
color=$([ "$HAS_COLOR" = true ] && echo "yes" || echo "no")
lang=$LANG
motd=$([ "$MOTD_CHOICE" = "y" ] && echo "yes" || echo "no")
motd_ssl=$([ "$MOTD_SSL_CHOICE" = "y" ] && echo "yes" || echo "no")
EOF
log "Config created: $CONFIG_FILE"

# === Обновление ===
if [ "$UPGRADE_CHOICE" = "y" ]; then
    log "${YELLOW}Обновление системы...${NC}"
    apt-get update && apt-get upgrade -y >> "$LOG_FILE" 2>&1 || log "Upgrade warning: continued anyway"
fi

# === Зависимости ===
log "${YELLOW}Установка socat, git, curl, dnsutils, lsb-release...${NC}"
apt-get install -y socat git curl bind9-dnsutils lsb-release >> "$LOG_FILE" 2>&1

# === Скачивание ===
log "${YELLOW}Скачивание acme_helper.sh...${NC}"
curl -fsSL "$REPO_RAW/acme_helper.sh" -o "$ACME_HELPER_SCRIPT"
chmod +x "$ACME_HELPER_SCRIPT"

# === acme.sh ===
log "${YELLOW}Установка acme.sh...${NC}"
if [ ! -d "$ACME_SH_DIR" ]; then
    git clone https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh >> "$LOG_FILE" 2>&1
    cd /tmp/acme.sh
    ./acme.sh --install --home "$ACME_SH_DIR" --no-cron --no-profile >> "$LOG_FILE" 2>&1
    rm -rf /tmp/acme.sh
else
    source "$ACME_SH_DIR/acme.sh"
    _upgrade
fi
source "$ACME_SH_DIR/acme.sh"
_set_default_ca_ letsencrypt

# === Алиас ===
ALIAS_CMD='[ -f /root/.acme_helper/acme_helper.sh ] && alias acme_helper='"'"'/root/.acme_helper/acme_helper.sh'"'"' || alias acme_helper='"'"'echo "acme_helper not found"'"'"''
if ! grep -q "acme_helper=" /root/.bashrc; then
    echo "$ALIAS_CMD" >> /root/.bashrc
    log "Alias added to .bashrc (no sudo for root)"
fi

# === MOTD ===
update_motd_helper() {
    local motd_text="$1"
    local ssl_line="$2"
    local motd_script="/etc/update-motd.d/10-acme-helper"
    if command -v lsb_release >/dev/null 2>&1 && lsb_release -i 2>/dev/null | grep -qi ubuntu; then
        # Ubuntu: dynamic MOTD
        cat > "$motd_script" <<EOF
#!/bin/sh
[ -z "\$SSH_CLIENT" ] && [ -z "\$SSH_TTY" ] && exit 0
echo "$motd_text"
[ "$ssl_line" = "yes" ] && echo "ssl: \$(ls "$ACME_SH_DIR"/*_ecc 2>/dev/null | xargs -n1 basename | sed 's/_ecc\$//' | tr '\n' ' ' | sed 's/ \$//')" || echo ""
EOF
        chmod +x "$motd_script"
        if command -v run-parts >/dev/null 2>&1; then
            run-parts /etc/update-motd.d/ > /run/motd.dynamic 2>/dev/null || true
        fi
        log "MOTD updated for Ubuntu"
    else
        # Debian/other: static /etc/motd
        if [ "$MOTD_CHOICE" = "y" ]; then
            echo "$motd_text" >> /etc/motd
        fi
        if [ "$MOTD_SSL_CHOICE" = "y" ]; then
            echo "ssl: \$(ls "$ACME_SH_DIR"/*_ecc 2>/dev/null | xargs -n1 basename | sed 's/_ecc\$//' | tr '\n' ' ' | sed 's/ \$//')" >> /etc/motd
        fi
        log "MOTD appended to /etc/motd"
    fi
}

MOTD_TEXT=$([ "$LANG" = "en" ] && echo "acme_helper - Script that simplifies working with acme.sh" || echo "acme_helper - Скрипт который упрощает работу с acme.sh")
if [ "$MOTD_CHOICE" = "y" ]; then
    update_motd_helper "$MOTD_TEXT" "$MOTD_SSL_CHOICE"
fi

# === Завершение ===
log "${GREEN}Установка завершена!${NC}"
echo -e "$TXT_DONE"
read -r -p "Press enter to run acme_helper now... " _  # Ignore input
source /root/.bashrc
acme_helper
