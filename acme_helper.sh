#!/bin/bash

# acme_helper - обёртка для acme.sh
# Автор: @RenaWayne

set -e
export LC_ALL=C

INSTALL_DIR="/root/.acme_helper"
CONFIG_FILE="$INSTALL_DIR/config"
ACME_SH="/root/.acme.sh/acme.sh"
LOG_DIR="$INSTALL_DIR/logs"
DATE_START=$(date +"%Y%m%d")
LOG_FILE="$LOG_DIR/log${DATE_START}.log"

mkdir -p "$LOG_DIR"

# === Загрузка конфига (безопасно) ===
if [ -f "$CONFIG_FILE" ]; then
    # Читаем как env vars, без source (чтобы избежать syntax errors)
    eval $(cat "$CONFIG_FILE" | grep -E '^(color|lang|motd|motd_ssl)=' | sed 's/=/="/; s/$/"/')
else
    color="no"
    lang="ru"
    motd="no"
    motd_ssl="no"
fi

# === Цвета ===
if [ "$color" = "yes" ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_exec() { "$@" 2>&1 | while IFS= read -r line; do log_exec_line "$line"; done; log_exec_line() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }; }

# === Тексты ===
if [ "$lang" = "en" ]; then
    TXT_CA="Current CA: "
    TXT_CERTS="Existing certificates: "
    TXT_NONE="none"
    TXT_MENU="Menu:\n1) Create new certificate\n2) Check TXT DNS record\n3) Re-issue certificate\n4) Check auto-renewal\n5) Select CA\n6) Info\n7) Delete certificate\n\n0 or enter) Exit"
    TXT_INPUT_DOMAINS="Enter domains (space/comma separated): example.ru *.example.ru"
    TXT_ADD_DNS="Add DNS TXT record:\nDomain: %s\nValue: \"%s\"\n"
    TXT_CHECK_TXT="Select domain to check TXT:"
    TXT_NO_RECORD="dig> Domain \"%s\". Record not found.\nenter) retry / 0) menu"
    TXT_FOUND="dig> Domain \"%s\". Record found: %s"
    TXT_RENEW="Select domain to renew."
    TXT_WAITING="--- Waiting for re-issue ---"
    TXT_OTHERS="--- Other domains ---"
    TXT_CRON_OK="acme.sh cron job active."
    TXT_CRON_NO="No acme.sh cron job."
    TXT_CHANGE_CA="Change CA: $ACME_SH --set-default-ca --server <ca>\nList: https://github.com/acmesh-official/acme.sh/wiki/Server\nenter) menu"
    TXT_INFO="acme_helper by @RenaKawayne[](https://github.com/renawayne/acme_helper)\nacme.sh: https://github.com/acmesh-official/acme.sh\nFiles:\nacme.sh: $ACME_SH\nHelper: $0\nConfig: $CONFIG_FILE\nLogs: $LOG_DIR\nMOTD: /etc/update-motd.d/10-acme-helper or /etc/motd"
    TXT_DELETE="Select cert to delete:"
    TXT_DELETED="Cert %s deleted."
else
    TXT_CA="Текущий центр: "
    TXT_CERTS="Сертификаты: "
    TXT_NONE="нет"
    TXT_MENU="Меню:\n1) Новый сертификат\n2) Проверить TXT DNS\n3) Перевыпустить\n4) Авто-обновление\n5) Центр сертификации\n6) Инфо\n7) Удалить сертификат\n\n0 или enter) Выход"
    TXT_INPUT_DOMAINS="Домены (пробел/запятая): example.ru *.example.ru"
    TXT_ADD_DNS="Добавьте TXT в DNS:\nДомен: %s\nЗначение: \"%s\"\n"
    TXT_CHECK_TXT="Выберите домен для TXT:"
    TXT_NO_RECORD="dig> Домен \"%s\". Не найдена.\nenter) повторить / 0) меню"
    TXT_FOUND="dig> Домен \"%s\". Найдена: %s"
    TXT_RENEW="Выберите домен для renew."
    TXT_WAITING="-=-=-=- Ожидают перевыпуска -=-=-=-"
    TXT_OTHERS="-=-=-=- Остальные -=-=-=-"
    TXT_CRON_OK="Crontab acme.sh активен."
    TXT_CRON_NO="Crontab acme.sh не найден."
    TXT_CHANGE_CA="Смена CA: $ACME_SH --set-default-ca --server <ca>\nСписок: https://github.com/acmesh-official/acme.sh/wiki/Server\nenter) меню"
    TXT_INFO="acme_helper от @RenaKawayne[](https://github.com/renawayne/acme_helper)\nacme.sh: https://github.com/acmesh-official/acme.sh\nФайлы:\nacme.sh: $ACME_SH\nHelper: $0\nConfig: $CONFIG_FILE\nЛоги: $LOG_DIR\nMOTD: /etc/update-motd.d/10-acme-helper или /etc/motd"
    TXT_DELETE="Выберите сертификат для удаления:"
    TXT_DELETED="Сертификат %s удалён."
fi

# === Функции ===
get_certs() {
    find "$ACME_SH_DIR" -maxdepth 1 -type d -name "*_ecc" 2>/dev/null | while read -r dir; do
        domain=$(basename "$dir" | sed 's/_ecc$//')
        ctime=$(stat -c %Y "$dir" 2>/dev/null || echo "0")
        echo "$ctime $domain"
    done | sort -nr | cut -d' ' -f2-
}

get_ca() {
    if [ -f "$ACME_SH_DIR/account.conf" ]; then
        grep "^DEFAULT_CA__=" "$ACME_SH_DIR/account.conf" 2>/dev/null | sed "s/.*='\(.*\)'.*/\1/" | xargs basename 2>/dev/null | sed 's/v02$//; s/api.letsencrypt.org$/letsencrypt/' || echo "letsencrypt"
    else
        echo "letsencrypt"
    fi
}

update_motd_ssl() {
    if [ "$motd_ssl" != "yes" ]; then return; fi
    local certs=$(get_certs | tr '\n' ' ' | sed 's/ $//' | sed 's/ /, /g')
    [ -z "$certs" ] && certs="$TXT_NONE"
    if command -v lsb_release >/dev/null 2>&1 && lsb_release -i 2>/dev/null | grep -qi ubuntu; then
        sed -i '/ssl:/d' /etc/update-motd.d/10-acme-helper 2>/dev/null || true
        echo "[ \"$certs\" != \"$TXT_NONE\" ] && echo \"ssl: $certs\"" >> /etc/update-motd.d/10-acme-helper
        run-parts /etc/update-motd.d/ > /run/motd.dynamic 2>/dev/null || true
    else
        sed -i '/ssl:/d' /etc/motd 2>/dev/null || true
        echo "ssl: $certs" >> /etc/motd
    fi
}

# === Основной цикл ===
while true; do
    clear
    echo -e "${GREEN}$TXT_CA$(get_ca)${NC}"
    local cert_list=$(get_certs)
    if [ -z "$cert_list" ]; then
        echo -e "${YELLOW}$TXT_CERTS$TXT_NONE${NC}"
    else
        echo -e "${GREEN}$TXT_CERTS${NC}"
        echo "$cert_list" | nl -w2 -s') '
    fi
    echo
    echo -e "${BLUE}$TXT_MENU${NC}"
    read -r choice
    log "User choice: $choice"

    case "$choice" in
        1)
            echo -e "${CYAN}$TXT_INPUT_DOMAINS${NC}"
            read -r domains_input
            domains=$(echo "$domains_input" | tr ', ' '\n' | tr '\n' ' -d ' | sed 's/^/ -d /')
            cmd="$ACME_SH --issue $domains --dns --force --yes-I-know-dns-manual-mode-enough-go-ahead-please"
            log_exec $cmd
            # Парс TXT (простой grep)
            $cmd 2>&1 | grep -E "(Domain:|TXT value:)" | while read -r line; do
                if [[ $line =~ Domain:\ (.*) ]]; then d="${BASH_REMATCH[1]}"; fi
                if [[ $line =~ TXT\ value:\ \'(.*)\' ]]; then v="${BASH_REMATCH[1]}"; printf "${TXT_ADD_DNS}\n" "$d" "$v"; fi
            done
            read -r -p "enter) menu... "
            ;;
        2)
            certs=($(get_certs))
            if [ ${#certs[@]} -eq 0 ]; then echo -e "${RED}Нет сертификатов${NC}"; read -r; continue; fi
            echo -e "${CYAN}$TXT_CHECK_TXT${NC}"
            PS3="Choice: "
            select domain in "${certs[@]}" "0) menu"; do
                [ "$REPLY" = "0" ] && break
                domain="${certs[$((REPLY-1))]:-${certs[0]}}"
                challenge="_acme-challenge.$domain"
                result=$(dig txt +short "$challenge" @8.8.8.8 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
                if [ -z "$result" ]; then
                    echo -e "${RED}$(printf "$TXT_NO_RECORD" "$challenge")${NC}"
                else
                    echo -e "${GREEN}$(printf "$TXT_FOUND" "$challenge" "$result")${NC}"
                fi
                read -r -p "enter) retry / 0) menu: " subchoice
                [ "$subchoice" = "0" ] && break
            done
            ;;
        3)
            # Waiting: conf with Le_DNSManual (manual mode)
            mapfile -t waiting < <(find "$ACME_SH_DIR" -name "*.conf" -exec grep -l "Le_DNSManual" {} \; 2>/dev/null | xargs -n1 basename | sed 's/\.conf$//' | sort -r)
            mapfile -t all_certs < <(get_certs)
            echo -e "${CYAN}$TXT_RENEW${NC}"
            if [ ${#waiting[@]} -gt 0 ]; then
                echo -e "${YELLOW}$TXT_WAITING${NC}"
                PS3="Choice: "
                select d in "${waiting[@]}" "0) next"; do
                    [ "$REPLY" = "0" ] && break
                    d="${waiting[$((REPLY-1))]:-${waiting[0]}}"
                    log_exec $ACME_SH --renew -d "$d" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please
                    read -r -p "enter... "
                    break 2
                done
            fi
            if [ ${#all_certs[@]} -gt 0 ]; then
                echo -e "${BLUE}$TXT_OTHERS${NC}"
                PS3="Choice: "
                select d in "${all_certs[@]}" "0) menu"; do
                    [ "$REPLY" = "0" ] && break
                    d="${all_certs[$((REPLY-1))]:-${all_certs[0]}}"
                    log_exec $ACME_SH --renew -d "$d" --force
                    read -r -p "enter... "
                    break
                done
            fi
            ;;
        4)
            if crontab -l 2>/dev/null | grep -q "$ACME_SH.*--cron"; then
                echo -e "${GREEN}$TXT_CRON_OK${NC}"
            else
                echo -e "${RED}$TXT_CRON_NO${NC}"
            fi
            read -r -p "enter... "
            ;;
        5)
            echo -e "${YELLOW}$TXT_CHANGE_CA${NC}"
            read -r
            ;;
        6)
            echo -e "${CYAN}$TXT_INFO${NC}"
            read -r
            ;;
        7)
            certs=($(get_certs))
            if [ ${#certs[@]} -eq 0 ]; then echo -e "${RED}Нет сертификатов${NC}"; read -r; continue; fi
            echo -e "${RED}$TXT_DELETE${NC}"
            PS3="Choice: "
            select domain in "${certs[@]}" "0) cancel"; do
                [ "$REPLY" = "0" ] && break
                domain="${certs[$((REPLY-1))]:-${certs[0]}}"
                log_exec $ACME_SH --remove -d "$domain"
                rm -rf "$ACME_SH_DIR/${domain}_ecc"
                echo -e "${GREEN}$(printf "$TXT_DELETED" "$domain")${NC}"
                update_motd_ssl
                read -r
                break
            done
            ;;
        0|"") break ;;
        *) echo "Invalid choice"; read -r ;;
    esac
    update_motd_ssl
done

echo -e "${GREEN}До свидания!${NC}"
