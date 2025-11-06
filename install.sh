#!/bin/bash

# acme_helper installer
# https://github.com/renawayne/acme_helper

set -e

# === Константы ===
INSTALL_DIR="/root/.acme_helper"
LOG_DIR="$INSTALL_DIR/logs"
CONFIG_FILE="$INSTALL_DIR/config"
ACME_HELPER_SCRIPT="$INSTALL_DIR/acme_helper.sh"
ACME_SH_DIR="/root/.acme.sh"
REPO_RAW="https://raw.githubusercontent.com/renawayne/acme_helper/main"
DATE_START=$(date +"%Y%m%d")
LOG_FILE="$LOG_DIR/log${DATE_START}.log"

# === Цвета ===
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    HAS_COLOR=true
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
    HAS_COLOR=false
fi

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

prompt() {
    local prompt_text="$1"
    local default="$2"
    local input
    echo -ne "${CYAN}$prompt_text${NC}"
    read -r input
    echo "$input" >> "$LOG_FILE"
    echo "$input" | grep -q . && echo "$input" || echo "$default"
}

# === Создание директорий ===
mkdir -p "$INSTALL_DIR" "$LOG_DIR"
> "$LOG_FILE"

log "${GREEN}=== Установка acme_helper ===${NC}"

# === Проверка цветов ===
if $HAS_COLOR; then
    COLOR_SUPPORT="yes"
else
    COLOR_SUPPORT="no"
fi

# === Язык ===
LANG_CHOICE=$(prompt "you language?\nru or en (or press enter. default: ru): " "ru")
case "$LANG_CHOICE" in
    en|EN) LANG="en" ;;
    *) LANG="ru" ;;
esac

# === Тексты ===
if [ "$LANG" = "en" ]; then
    TXT_INSTALLING="This script will install \"https://github.com/renawayne/acme_helper/\" on your machine. The script is launched via alias in .bashrc (acme_helper).\nThe script simplifies working with \"https://github.com/acme.sh\".\nAdd reminder about the script in motd?\nExample:\n...your motd\nacme_helper - Script that simplifies working with acme.sh\n...\ny or n (or press enter. default: y): "
    TXT_MOTD_SSL="Add reminder about existing certificates in motd? (script will search folders /root/.acme.sh/*_ecc/ and display them.\nExample:\n...your motd\nacme_helper - Script that simplifies working with acme.sh\nssl: example.ru , example.com\n...\ny or n (or press enter. default: y): "
    TXT_UPGRADE="Run \"sudo apt-get update && sudo apt-get upgrade -y\"?\ny or n (or press enter. default: y): "
    TXT_DONE="Script installed. Use acme_helper to run it or press enter to launch now.\nAlias added to .bashrc. If you press enter, the script will reload bash, show motd and run via alias.\nIf not started, check \"/root/.acme_helper/acme_helper.sh\"\nacme.sh installed in \"/root/.acme.sh/acme.sh\""
    TXT_CA="Current CA: "
    TXT_CERTS="Existing certificates: "
    TXT_NONE="none"
    TXT_MENU="Menu:\n1) Create new certificate\n2) Check TXT DNS record\n3) Re-issue certificate\n4) Check auto-renewal\n5) Select CA\n6) Info\n7) Delete certificate\n\n0 or enter) Exit"
    TXT_INPUT_DOMAINS="To create a certificate, enter domain names separated by space or comma. Example:\nexample.ru *.example.ru\nor\nexample.ru , *.example.ru\nEnter domains: "
    TXT_ADD_DNS="Add DNS record on server:\nType: TXT\nDomain: %s\nTXT value: \"%s\"\n"
    TXT_CHECK_TXT="Check via \"dig txt +short _acme-challenge.example.ru\".\nSelect domain to check:"
    TXT_NO_RECORD="dig> Domain \"%s\". Record not found."
    TXT_FOUND="dig> Domain \"%s\". Record found: %s"
    TXT_RENEW="To re-issue after DNS update, select domain."
    TXT_WAITING="--- Waiting for re-issue ---"
    TXT_OTHERS="--- Other domains ---"
    TXT_CRON_OK="Cron job for acme.sh found and active."
    TXT_CRON_NO="No acme.sh cron job found."
    TXT_CHANGE_CA="To change CA manually:\n\"/root/.acme.sh/acme.sh --set-default-ca --server <ca>\".\nList: https://github.com/acmesh-official/acme.sh/wiki/Server\nenter) back to menu"
    TXT_INFO="acme_helper - wrapper for acme.sh\nAuthor: @RenaKawayne[](https://github.com/renawayne)\nacme.sh: https://github.com/acmesh-official/acme.sh\n\nFiles:\nacme.sh: /root/.acme.sh/acme.sh\nHelper: /root/.acme_helper/acme_helper.sh\nConfig: /root/.acme_helper/config\nLogs: /root/.acme_helper/logs/\nMOTD: /etc/motd or /etc/update-motd.d/"
    TXT_DELETE="Select certificate to delete:"
    TXT_DELETED="Certificate %s deleted."
else
    TXT_INSTALLING="Этот скрипт установит \"https://github.com/renawayne/acme_helper/\" на вашу машину. Скрипт запускается через alias в .bashrc (acme_helper).\nСкрипт упрощает работу с \"https://github.com/acme.sh\".\nДобавить напоминание о скрипте в motd?\nПример:\n...your motd\nacme_helper - Скрипт который упрощает работу с acme.sh\n...\ny or n (или enter. default: y): "
    TXT_MOTD_SSL="Добавить напоминание о существующих сертификатах в motd? (скрипт будет искать папки /root/.acme.sh/*_ecc/ и выводить их.\nПример:\n...your motd\nacme_helper - Скрипт который упрощает работу с acme.sh\nssl: example.ru , example.com\n...\ny or n (или enter. default: y): "
    TXT_UPGRADE="Выполнить \"sudo apt-get update && sudo apt-get upgrade -y\"?\ny or n (или enter. default: y): "
    TXT_DONE="Скрипт установлен. Используйте acme_helper, чтобы запустить или нажмите enter для запуска сейчас.\nАлиас добавлен в .bashrc. При enter — перезагрузка bash, motd и запуск через алиас.\nЕсли не запустился — проверьте \"/root/.acme_helper/acme_helper.sh\"\nacme.sh установлен в \"/root/.acme.sh/acme.sh\""
    TXT_CA="Текущий центр сертификации: "
    TXT_CERTS="Существующие сертификаты: "
    TXT_NONE="нет"
    TXT_MENU="Меню:\n1) Создать новый сертификат\n2) Проверить TXT запись DNS\n3) Перевыпустить сертификат\n4) Проверка авто-обновления\n5) Выбрать центр сертификации\n6) Информация\n7) Удаление сертификата\n\n0 или enter) Выход"
    TXT_INPUT_DOMAINS="Для создания сертификата введите домены через пробел или запятую. Пример:\nexample.ru *.example.ru\nили\nexample.ru , *.example.ru\nВведите домены: "
    TXT_ADD_DNS="Добавьте на сервер DNS запись:\nТип: TXT\nДомен: %s\nЗначение TXT: \"%s\"\n"
    TXT_CHECK_TXT="Проверка через \"dig txt +short _acme-challenge.example.ru\".\nВыберите домен для проверки:"
    TXT_NO_RECORD="dig> Домен \"%s\". Запись не найдена."
    TXT_FOUND="dig> Домен \"%s\". Запись найдена: %s"
    TXT_RENEW="Для возобновления выдачи сертификата после обновления DNS, выберите домен."
    TXT_WAITING="-=-=-=- Ожидают перевыпуска -=-=-=-"
    TXT_OTHERS="-=-=-=- Остальные домены -=-=-=-"
    TXT_CRON_OK="Задание crontab для acme.sh найдено и активно."
    TXT_CRON_NO="Задание crontab для acme.sh не найдено."
    TXT_CHANGE_CA="Для смены центра вручную:\n\"/root/.acme.sh/acme.sh --set-default-ca --server <ca>\".\nСписок: https://github.com/acmesh-official/acme.sh/wiki/Server\nenter) в главное меню"
    TXT_INFO="acme_helper - обёртка для acme.sh\nАвтор: @RenaKawayne[](https://github.com/renawayne)\nacme.sh: https://github.com/acmesh-official/acme.sh\n\nФайлы:\nacme.sh: /root/.acme.sh/acme.sh\nПомощник: /root/.acme_helper/acme_helper.sh\nКонфиг: /root/.acme_helper/config\nЛоги: /root/.acme_helper/logs/\nMOTD: /etc/motd или /etc/update-motd.d/"
    TXT_DELETE="Выберите сертификат для удаления:"
    TXT_DELETED="Сертификат %s удалён."
fi

# === Вопросы ===
MOTD_CHOICE=$(prompt "$TXT_INSTALLING" "y")
MOTD_SSL_CHOICE=$(prompt "$TXT_MOTD_SSL" "y")
UPGRADE_CHOICE=$(prompt "$TXT_UPGRADE" "y")

# === Конфиг ===
cat > "$CONFIG_FILE" <<EOF
color=$COLOR_SUPPORT
lang=$LANG
motd=$(echo "$MOTD_CHOICE" | grep -i '^y' && echo "yes" || echo "no")
motd_ssl=$(echo "$MOTD_SSL_CHOICE" | grep -i '^y' && echo "yes" || echo "no")
EOF

# === Обновление системы ===
if echo "$UPGRADE_CHOICE" | grep -i '^y'; then
    log "${YELLOW}Обновление системы...${NC}"
    apt-get update && apt-get upgrade -y >> "$LOG_FILE" 2>&1
fi

# === Установка зависимостей ===
log "${YELLOW}Установка socat, git, curl, dig...${NC}"
apt-get install -y socat git curl bind9-utils >> "$LOG_FILE" 2>&1

# === Скачивание acme_helper.sh ===
log "${YELLOW}Скачивание acme_helper.sh...${NC}"
curl -fsSL "$REPO_RAW/acme_helper.sh" -o "$ACME_HELPER_SCRIPT"
chmod +x "$ACME_HELPER_SCRIPT"

# === Установка acme.sh ===
log "${YELLOW}Установка acme.sh...${NC}"
if [ ! -d "$ACME_SH_DIR" ]; then
    git clone https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh >> "$LOG_FILE" 2>&1
    cd /tmp/acme.sh
    ./acme.sh --install --home "$ACME_SH_DIR" --nocron >> "$LOG_FILE" 2>&1
    rm -rf /tmp/acme.sh
else
    "$ACME_SH_DIR/acme.sh" --upgrade >> "$LOG_FILE" 2>&1
fi

# === Установка CA ===
"$ACME_SH_DIR/acme.sh" --set-default-ca --server letsencrypt >> "$LOG_FILE" 2>&1

# === Алиас в .bashrc ===
if ! grep -q "alias acme_helper=" /root/.bashrc; then
    echo "alias acme_helper='sudo $ACME_HELPER_SCRIPT'" >> /root/.bashrc
fi

# === MOTD ===
update_motd() {
    local content="$1"
    if [ -d /etc/update-motd.d ]; then
        echo "$content" > /etc/update-motd.d/99-acme-helper
        chmod +x /etc/update-motd.d/99-acme-helper
    else
        echo "$content" >> /etc/motd
    fi
}

if echo "$MOTD_CHOICE" | grep -i '^y'; then
    MOTD_TEXT="acme_helper - Скрипт который упрощает работу с acme.sh"
    [ "$LANG" = "en" ] && MOTD_TEXT="acme_helper - Script that simplifies working with acme.sh"
    update_motd "$MOTD_TEXT"
fi

# === Завершение ===
log "${GREEN}Установка завершена!${NC}"
echo "$TXT_DONE"
read -r -p "Press enter to run acme_helper now..." || true
if [ -t 0 ]; then
    exec bash
    acme_helper
fi
