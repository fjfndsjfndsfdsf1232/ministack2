# site_bulk_delete.sh - Команда для массового удаления сайтов в MiniStack CLI
# Версия 1.0.31

bulk_delete_sites() {
    clean_old_logs
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --bulk-delete: $@. Используйте без флагов"
        exit 1
    fi
    log_message "info" "Запускаем массовое удаление сайтов..." "start_operation"
    echo -e "${YELLOW}Введите домены (по одному на строку, без http:// или /, например: domain.com). Для завершения введите 'done':${NC}"
    declare -a INPUT_DOMAINS
    while true; do
        read -r domain
        if [ "$domain" = "done" ]; then
            break
        fi
        if [ -z "$domain" ]; then
            continue
        fi
        INPUT_DOMAINS+=("$domain")
    done

    if [ ${#INPUT_DOMAINS[@]} -eq 0 ]; then
        log_message "error" "Не введено ни одного домена"
        exit 1
    fi

    declare -a VALID_DOMAINS
    declare -a ORIGINAL_DOMAINS
    for domain in "${INPUT_DOMAINS[@]}"; do
        cleaned_domain=$(clean_domain "$domain")
        if echo "$cleaned_domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            punycode_domain=$(convert_to_punycode "$cleaned_domain")
            VALID_DOMAINS+=("$punycode_domain")
            ORIGINAL_DOMAINS+=("$cleaned_domain")
        fi
    done

    if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
        log_message "error" "Нет валидных доменов для удаления"
        exit 1
    fi

    SUCCESS_COUNT=0
    ERROR_COUNT=0
    VALID_DOMAINS_COUNT=${#VALID_DOMAINS[@]}
    for i in "${!VALID_DOMAINS[@]}"; do
        domain="${VALID_DOMAINS[$i]}"
        original_domain="${ORIGINAL_DOMAINS[$i]}"
        log_message "info" "Обработка домена $original_domain (Punycode: $domain)"
        if ! check_site_not_exists "$domain"; then
            ((ERROR_COUNT++))
            continue
        fi

        log_message "info" "Удаляем сайт $original_domain..."
        WEB_ROOT="/var/www/$domain"
        CONFIG_FILE="/etc/nginx/sites-available/$domain"
        ENABLED_FILE="/etc/nginx/sites-enabled/$domain"
        DB_NAME=$(domain_to_db_name "$domain")
        CERT_PATH="/etc/letsencrypt/live/$domain"
        DB_ROOT_PASS=$(get_db_root_pass)
        if [ -d "$CERT_PATH" ]; then
            certbot delete --cert-name "$domain" --non-interactive
            if [ ! -d "$CERT_PATH" ]; then
                log_message "success" "SSL-сертификаты для $original_domain удалены"
            else
                log_message "error" "SSL-сертификаты для $original_domain не удалены"
                ((ERROR_COUNT++))
                continue
            fi
        fi
        [ -f "$ENABLED_FILE" ] && rm "$ENABLED_FILE"
        [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
        [ -d "$WEB_ROOT" ] && rm -rf "$WEB_ROOT"
        mysql -u root -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null
        mysql -u root -p"$DB_ROOT_PASS" -e "DROP USER IF EXISTS 'wp_$DB_NAME'@'localhost';" 2>/dev/null
        if grep -q "Site: $original_domain" "$SITE_CREDENTIALS"; then
            sed -i "/Site: $original_domain/,/-------------------/d" "$SITE_CREDENTIALS" 2>/dev/null
        fi
        if ! nginx -t >/dev/null 2>&1; then
            log_message "error" "Конфигурация Nginx невалидна после удаления"
            ((ERROR_COUNT++))
            continue
        fi
        systemctl restart nginx
        check_service nginx
        log_message "success" "Домен успешно удалён $original_domain"
        ((SUCCESS_COUNT++))
    done

    log_message "info" "Массовое удаление завершено" "end_operation" "Массовое удаление завершено"
}
