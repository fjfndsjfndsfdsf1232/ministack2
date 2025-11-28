# secure_ssl.sh - Команда для настройки SSL в MiniStack CLI
# Версия 1.0.31

setup_ssl() {
    clean_old_logs
    DOMAIN="$1"
    CERT_TYPE="$2"
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    if [ -z "$DOMAIN" ]; then
        log_message "error" "Укажите домен после --ssl, например: sudo ms secure --ssl example.com [--letsencrypt|--selfsigned]"
        exit 1
    fi
    if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_message "error" "Невалидный домен: $DOMAIN. Домен должен содержать точку"
        exit 1
    fi
    if [ $# -gt 2 ]; then
        log_message "error" "Неверные аргументы для --ssl: ${@:3}. Используйте --letsencrypt или --selfsigned"
        exit 1
    fi
    if [ -z "$CERT_TYPE" ]; then
        CERT_TYPE="--letsencrypt"
    fi
    if [[ "$CERT_TYPE" != "--letsencrypt" && "$CERT_TYPE" != "--selfsigned" ]]; then
        log_message "error" "Неверный тип сертификата: $CERT_TYPE. Используйте --letsencrypt или --selfsigned"
        exit 1
    fi
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Настраиваем SSL для $ORIGINAL_DOMAIN (Punycode: $DOMAIN) с типом $CERT_TYPE..." "start_operation"
    CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    WEB_ROOT="/var/www/$DOMAIN/html"

    if [ "$CERT_TYPE" = "--letsencrypt" ]; then
        if ! command -v certbot >/dev/null 2>&1; then
            log_message "error" "Certbot не установлен"
            exit 1
        fi
        if [[ $(echo "$DOMAIN" | grep -o "\." | wc -l) -gt 1 ]]; then
            certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$ORIGINAL_DOMAIN
        else
            certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email admin@$ORIGINAL_DOMAIN
        fi
        if grep -q "listen 443 ssl" "$CONFIG_FILE"; then
            log_message "success" "SSL (Let's Encrypt) успешно установлен для $ORIGINAL_DOMAIN"
        else
            log_message "error" "SSL (Let's Encrypt) не установлен для $ORIGINAL_DOMAIN"
            ERROR_COUNT=1
            log_message "info" "Настройка SSL завершена" "end_operation" "Настройка SSL завершена"
            exit 1
        fi
    else
        mkdir -p /etc/ssl/private /etc/ssl/certs
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/$DOMAIN.key -out /etc/ssl/certs/$DOMAIN.crt -subj "/CN=$DOMAIN" || { log_message "error" "Не удалось создать самоподписанный сертификат"; exit 1; }
        chmod 600 /etc/ssl/private/$DOMAIN.key
        log_message "success" "Самоподписанный SSL-сертификат создан для $ORIGINAL_DOMAIN"
        sed -i '/listen 80;/a\    listen 443 ssl;\n    ssl_certificate /etc/ssl/certs/'"$DOMAIN"'.crt;\n    ssl_certificate_key /etc/ssl/private/'"$DOMAIN"'.key;' "$CONFIG_FILE"
        if grep -q "listen 443 ssl" "$CONFIG_FILE"; then
            log_message "success" "SSL (самоподписанный) успешно установлен для $ORIGINAL_DOMAIN"
        else
            log_message "error" "SSL (самоподписанный) не установлен для $ORIGINAL_DOMAIN"
            ERROR_COUNT=1
            log_message "info" "Настройка SSL завершена" "end_operation" "Настройка SSL завершена"
            exit 1
        fi
    fi

    if [ -f "$WEB_ROOT/wp-config.php" ]; then
        DB_ROOT_PASS=$(get_db_root_pass)
        DB_NAME=$(domain_to_db_name "$DOMAIN")
        WP_URL="https://$DOMAIN"
        sudo -u www-data wp config set WP_SITEURL "$WP_URL" --allow-root --path="$WEB_ROOT" >/dev/null 2>&1
        sudo -u www-data wp option update siteurl "$WP_URL" --allow-root --path="$WEB_ROOT" >/dev/null 2>&1
        log_message "success" "WP_SITEURL обновлен на $WP_URL"
    fi
    if grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        sed -i "/Site: $ORIGINAL_DOMAIN/,/-------------------/{/SSL: .*/s//SSL: Enabled ($CERT_TYPE)/}" "$SITE_CREDENTIALS" 2>/dev/null
        log_message "success" "Статус SSL обновлен в $SITE_CREDENTIALS"
    fi
    if ! grep -q "Strict-Transport-Security" "$CONFIG_FILE"; then
        sed -i '/include \/etc\/nginx\/common\/security_headers.conf;/a\    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;' "$CONFIG_FILE"
    fi
    nginx -t && systemctl restart nginx
    check_service nginx
    log_message "success" "SSL и HSTS настроены для $ORIGINAL_DOMAIN!"
    SUCCESS_COUNT=1
    log_message "info" "Настройка SSL завершена" "end_operation" "Настройка SSL завершена"
}
