# site_delete.sh - Команда для удаления одного сайта в MiniStack CLI
# Версия 1.0.31

delete_site() {
    clean_old_logs
    DOMAIN="$1"
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    if [ -z "$DOMAIN" ]; then
        log_message "error" "Укажите домен после --delete, например: sudo ms site --delete example.com"
        exit 1
    fi
    if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_message "error" "Невалидный домен: $DOMAIN. Домен должен содержать точку"
        exit 1
    fi
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Удаляем сайт $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    if ! check_site_not_exists "$DOMAIN"; then
        ERROR_COUNT=1
        log_message "info" "Удаление сайта завершено" "end_operation" "Удаление сайта завершено"
        exit 1
    fi
    WEB_ROOT="/var/www/$DOMAIN"
    CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    ENABLED_FILE="/etc/nginx/sites-enabled/$DOMAIN"
    DB_NAME=$(domain_to_db_name "$DOMAIN")
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    DB_ROOT_PASS=$(get_db_root_pass)
    if [ -d "$CERT_PATH" ]; then
        certbot delete --cert-name "$DOMAIN" --non-interactive
        if [ ! -d "$CERT_PATH" ]; then
            log_message "success" "SSL-сертификаты для $ORIGINAL_DOMAIN удалены"
        else
            log_message "error" "SSL-сертификаты для $ORIGINAL_DOMAIN не удалены"
            ERROR_COUNT=1
            log_message "info" "Удаление сайта завершено" "end_operation" "Удаление сайта завершено"
            exit 1
        fi
    fi
    [ -f "$ENABLED_FILE" ] && rm "$ENABLED_FILE"
    [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
    [ -d "$WEB_ROOT" ] && rm -rf "$WEB_ROOT"
    mysql -u root -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null
    mysql -u root -p"$DB_ROOT_PASS" -e "DROP USER IF EXISTS 'wp_$DB_NAME'@'localhost';" 2>/dev/null
    if grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        sed -i "/Site: $ORIGINAL_DOMAIN/,/-------------------/d" "$SITE_CREDENTIALS" 2>/dev/null
    fi
    if ! nginx -t >/dev/null 2>&1; then
        log_message "error" "Конфигурация Nginx невалидна после удаления"
        ERROR_COUNT=1
        log_message "info" "Удаление сайта завершено" "end_operation" "Удаление сайта завершено"
        exit 1
    fi
    systemctl restart nginx
    check_service nginx
    log_message "success" "Домен успешно удалён $ORIGINAL_DOMAIN"
    SUCCESS_COUNT=1
    log_message "info" "Удаление сайта завершено" "end_operation" "Удаление сайта завершено"
}
