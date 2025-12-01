# site_app_key.sh - Команда для создания ключа приложения WordPress через wp-cli
# Версия 1.0.31

create_app_key() {
    clean_old_logs
    DOMAIN="$1"
    USERNAME="$2"
    APP_NAME="$3"
    
    if [ -z "$DOMAIN" ] || [ -z "$USERNAME" ] || [ -z "$APP_NAME" ]; then
        log_message "error" "Укажите домен, имя пользователя и название приложения, например: sudo ms site --app-key example.com admin MyApp"
        exit 1
    fi
    
    if [ $# -gt 3 ]; then
        log_message "error" "Неверные аргументы для --app-key: ${@:4}. Используйте: sudo ms site --app-key <domain> <username> <app-name>"
        exit 1
    fi
    
    if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_message "error" "Невалидный домен: $DOMAIN. Домен должен содержать точку"
        exit 1
    fi
    
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    
    log_message "info" "Создание ключа приложения для $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    
    # Проверяем, что сайт существует
    if ! grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        log_message "error" "Сайт $ORIGINAL_DOMAIN не найден в $SITE_CREDENTIALS"
        exit 1
    fi
    
    # Проверяем, что это WordPress сайт
    SITE_TYPE=$(grep -A11 "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS" | grep "^Type:" | sed 's/^Type: //')
    if [ "$SITE_TYPE" != "WordPress" ]; then
        log_message "error" "Сайт $ORIGINAL_DOMAIN не является WordPress сайтом (тип: $SITE_TYPE)"
        exit 1
    fi
    
    # Получаем путь к WordPress
    WEB_ROOT=$(grep -A11 "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS" | grep "^Path:" | sed 's/^Path: //')
    if [ -z "$WEB_ROOT" ]; then
        WEB_ROOT="/var/www/$DOMAIN/html"
    fi
    
    # Проверяем, что директория WordPress существует
    if [ ! -d "$WEB_ROOT" ]; then
        log_message "error" "Директория WordPress не найдена: $WEB_ROOT"
        exit 1
    fi
    
    # Проверяем, что wp-config.php существует
    if [ ! -f "$WEB_ROOT/wp-config.php" ]; then
        log_message "error" "Файл wp-config.php не найден в $WEB_ROOT"
        exit 1
    fi
    
    # Проверяем, что пользователь существует в WordPress
    cd "$WEB_ROOT"
    if ! sudo -u www-data wp user get "$USERNAME" --allow-root >/dev/null 2>&1; then
        log_message "error" "Пользователь $USERNAME не найден в WordPress"
        exit 1
    fi
    
    log_message "info" "Пользователь $USERNAME найден, создаем ключ приложения '$APP_NAME'..."
    
    # Создаем ключ приложения
    APP_PASSWORD=$(sudo -u www-data wp application-password create "$USERNAME" "$APP_NAME" --porcelain --allow-root 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$APP_PASSWORD" ]; then
        log_message "success" "Ключ приложения успешно создан!"
        log_message "info" "Имя пользователя: $USERNAME"
        log_message "info" "Название приложения: $APP_NAME"
        log_message "success" "Ключ приложения: $APP_PASSWORD"
        log_message "warning" "Сохраните этот ключ! Он больше не будет показан."
        
        # Сохраняем ключ в файл credentials
        init_credentials
        if grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
            # Добавляем информацию о ключе приложения перед разделителем
            # Используем временный файл для безопасной вставки
            TEMP_FILE=$(mktemp)
            awk -v domain="$ORIGINAL_DOMAIN" -v app_name="$APP_NAME" -v username="$USERNAME" -v app_password="$APP_PASSWORD" '
                /^Site: / { in_section = ($2 == domain) }
                in_section && /^-------------------$/ {
                    print "Application Key: " app_name " (" username ") - " app_password
                }
                { print }
            ' "$SITE_CREDENTIALS" > "$TEMP_FILE" && mv "$TEMP_FILE" "$SITE_CREDENTIALS"
            chmod 600 "$SITE_CREDENTIALS" 2>/dev/null
        fi
        
        SUCCESS_COUNT=1
        ERROR_COUNT=0
        log_message "info" "Создание ключа приложения завершено" "end_operation" "Создание ключа приложения завершено"
    else
        log_message "error" "Не удалось создать ключ приложения: $APP_PASSWORD"
        ERROR_COUNT=1
        SUCCESS_COUNT=0
        log_message "info" "Создание ключа приложения завершено" "end_operation" "Создание ключа приложения завершено"
        exit 1
    fi
}

