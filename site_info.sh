# site_info.sh - Команда для отображения информации о сайте в MiniStack CLI
# Версия 1.0.31

site_info() {
    clean_old_logs
    DOMAIN="$1"
    if [ -z "$DOMAIN" ]; then
        log_message "error" "Укажите домен после --info, например: sudo ms site --info example.com"
        exit 1
    fi
    if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_message "error" "Невалидный домен: $DOMAIN. Домен должен содержать точку"
        exit 1
    fi
    if [ $# -gt 1 ]; then
        log_message "error" "Неверные аргументы для --info: ${@:2}. Используйте только домен"
        exit 1
    fi
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Информация о сайте $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    if ! grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        log_message "error" "Сайт $ORIGINAL_DOMAIN не найден в $SITE_CREDENTIALS"
        exit 1
    fi
    CREDENTIALS=$(grep -A11 "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS" | sed 's/^/  /')
    echo -e "$CREDENTIALS"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Информация о сайте отображена" "end_operation" "Информация о сайте отображена"
}
