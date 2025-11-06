#!/bin/bash

# acme_helper - обёртка для acme.sh
# Автор: @RenaWayne

set -e

INSTALL_DIR="/root/.acme_helper"
CONFIG_FILE="$INSTALL_DIR/config"
ACME_SH="$HOME/.acme.sh/acme.sh"
LOG_DIR="$INSTALL_DIR/logs"
DATE_START=$(date +"%Y%m%d")
LOG_FILE="$LOG_DIR/log${DATE_START}.log"

mkdir -p "$LOG_DIR"

# === Загрузка конфига ===
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    color="no"
    lang="ru"
    motd="no"
    motd_ssl="no"
fi

# === Цвета ===
if [ "$color" = "yes" ] && [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
exec 3>&1
log_exec() { "$@" 2>&1 | tee -a "$LOG_FILE" >&3; }

# === Язык ===
case "$lang" in
    en) source <(sed 's/ru/en/g' "$0" | grep -A 200 '# === ТЕКСТЫ ===' | tail -n +2) ;;
esac

# === ТЕКСТЫ ===
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
TXT_CHANGE_CA="Для смены центра вручную:\n\"$ACME_SH --set-default-ca --server <ca>\".\nСписок: https://github.com/acmesh-official/acme.sh/wiki/Server\nenter) в главное меню"
TXT_INFO="acme_helper - обёртка для acme.sh\nАвтор: @RenaKawayne[](https://github.com/renawayne)\nacme.sh: https://github.com/acmesh-official/acme.sh\n\nФайлы:\nacme.sh: $ACME_SH\nПомощник: $0\nКонфиг: $CONFIG_FILE\nЛоги: $LOG_DIR\nMOTD: /etc/motd или /etc/update-motd.d/"
TXT_DELETE="Выберите сертификат для удаления:"
TXT_DELETED="Сертификат %s удалён."

# === Получение списка сертификатов ===
get_certs() {
    find "$HOME/.acme.sh" -maxdepth 1 -type d -name "*_ecc" | while read dir; do
        domain=$(basename "$dir" | sed 's/_ecc$//')
        ctime=$(stat -c %Y "$dir")
        echo "$ctime $domain $dir"
    done | sort -nr | cut -d' ' -f2-
}

# === Получение CA ===
get_ca() {
    if [ -f "$HOME/.acme.sh/account.conf" ]; then
        grep "DEFAULT_CA" "$HOME/.acme.sh/account.conf" | cut -d"'" -f2 | xargs -n1 basename 2>/dev/null || echo "letsencrypt"
    else
        echo "letsencrypt"
    fi
}

# === MOTD SSL ===
update_motd_ssl() {
    if [ "$motd_ssl" != "yes" ]; then return; fi
    local certs=$(get_certs | tr '\n' ' ' | sed 's/ $//')
    [ -z "$certs" ] && certs="none"
    local line="ssl: $certs"
    [ "$lang" = "en" ] && line="ssl: $certs"
    if [ -d /etc/update-motd.d ]; then
        sed -i '/ssl:/d' /etc/update-motd.d/99-acme-helper 2>/dev/null || true
        echo "$line" >> /etc/update-motd.d/99-acme-helper
    else
        sed -i '/ssl:/d' /etc/motd 2>/dev/null || true
        echo "$line" >> /etc/motd
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
        echo "$cert_list" | nl
    fi
    echo
    echo -e "${BLUE}$TXT_MENU${NC}"
    read -r choice
    echo "$choice" >> "$LOG_FILE"

    case "$choice" in
        1)
            echo -e "${CYAN}$TXT_INPUT_DOMAINS${NC}"
            read -r domains_input
            domains=$(echo "$domains_input" | tr ', ' ' ')
            cmd="$ACME_SH --issue $domains --dns --force --yes-I-know-dns-manual-mode-enough-go-ahead-please"
            output=$(log_exec $cmd) && ret=$? || ret=$?
            echo "$output"
            if [ $ret -eq 0 ]; then
                echo "$output" | grep -E "Domain:|_acme-challenge" | sed -E 's/.*Domain: (.*)/Домен: \1/; s/.*TXT value: (.*)/Значение TXT: "\1"/' | \
                while read -r line; do
                    if [[ $line == Домен:* ]]; then
                        d=$(echo "$line" | cut -d' ' -f2-)
                    elif [[ $line == Значение* ]]; then
                        v=$(echo "$line" | cut -d'"' -f2)
                        printf "$TXT_ADD_DNS" "$d" "$v"
                    fi
                done
            fi
            read -r -p "enter) в меню..."
            ;;
        2)
            mapfile -t certs <<< "$(get_certs)"
            if [ ${#certs[@]} -eq 0 ]; then
                echo -e "${RED}Нет сертификатов${NC}"
                read -r -p "enter..."
                continue
            fi
            echo -e "${CYAN}$TXT_CHECK_TXT${NC}"
            select domain in "${certs[@]}" "0) выход"; do
                [ "$domain" = "0) выход" ] && break
                [ -z "$domain" ] && domain="${certs[0]}"
                challenge="_acme-challenge.$domain"
                result=$(dig txt +short "$challenge" | tr '\n' ' ' | sed 's/ $//')
                if [ -z "$result" ]; then
                    echo -e "${RED}$(printf "$TXT_NO_RECORD" "$challenge")${NC}"
                else
                    echo -e "${GREEN}$(printf "$TXT_FOUND" "$challenge" "$result")${NC}"
                fi
                read -r -p "enter) повтор / 0) выход: " sub
                [ "$sub" = "0" ] && break
            done
            ;;
        3)
            mapfile -t waiting <<< $(find "$HOME/.acme.sh" -name "*.conf" -exec grep -l "Le_DNSManual" {} \; | xargs -I{} basename {} .conf | sort)
            mapfile -t all_certs <<< "$(get_certs)"
            echo -e "${CYAN}$TXT_RENEW${NC}"
            if [ ${#waiting[@]} -gt 0 ]; then
                echo -e "${YELLOW}$TXT_WAITING${NC}"
                select d in "${waiting[@]}" "0) выход"; do
                    [ "$d" = "0) выход" ] && break
                    log_exec $ACME_SH --renew -d "$d" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please
                    read -r -p "enter..."
                    break
                done
            fi
            if [ ${#all_certs[@]} -gt 0 ]; then
                echo -e "${BLUE}$TXT_OTHERS${NC}"
                select d in "${all_certs[@]}" "0) выход"; do
                    [ "$d" = "0) выход" ] && break
                    log_exec $ACME_SH --renew -d "$d" --force
                    read -r -p "enter..."
                    break
                done
            fi
            ;;
        4)
            if crontab -l 2>/dev/null | grep -q "acme.sh.*--cron"; then
                echo -e "${GREEN}$TXT_CRON_OK${NC}"
            else
                echo -e "${RED}$TXT_CRON_NO${NC}"
            fi
            read -r -p "enter..."
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
            mapfile -t certs <<< "$(get_certs)"
            if [ ${#certs[@]} -eq 0 ]; then
                echo -e "${RED}Нет сертификатов${NC}"
                read -r
                continue
            fi
            echo -e "${RED}$TXT_DELETE${NC}"
            select domain in "${certs[@]}" "0) отмена"; do
                [ "$domain" = "0) отмена" ] && break
                log_exec $ACME_SH --remove -d "$domain"
                echo -e "${GREEN}$(printf "$TXT_DELETED" "$domain")${NC}"
                rm -rf "$HOME/.acme.sh/${domain}_ecc"
                update_motd_ssl
                read -r
                break
            done
            ;;
        0|"") break ;;
    esac
    update_motd_ssl
done

echo -e "${GREEN}До свидания!${NC}"
