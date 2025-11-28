# core.sh - Вспомогательные функции для MiniStack CLI
# Версия 1.0.31

# Централизованная функция логирования
log_message() {
    local type="$1"
    local msg="$2"
    local context="$3"  # start_operation, end_operation, или пусто
    local timestamp_screen=$(date '+%H:%M:%S')
    local timestamp_file=$(date '+%Y-%m-%d %H:%M:%S')
    local color
    local prefix

    case "$type" in
        "success")
            color="$GREEN"
            prefix="INFO"
            ;;
        "info")
            color="$BLUE"
            prefix="INFO"
            ;;
        "error")
            color="$RED"
            prefix="ERROR"
            ;;
        "warning")
            color="$YELLOW"
            prefix="WARNING"
            ;;
        *)
            color="$BLUE"
            prefix="INFO"
            ;;
    esac

    # Добавляем разделитель для начала операции
    if [ "$context" = "start_operation" ]; then
        echo -e "${BLUE}=== MiniStack ===${NC}"
        echo -e "[${timestamp_file}] === MiniStack ===" >> "$LOG_FILE"
    fi

    # Логируем сообщение
    echo -e "${color}${prefix} [$timestamp_screen] $msg${NC}"
    echo -e "[${timestamp_file}] ${prefix} - $msg" >> "$LOG_FILE"

    # Добавляем разделитель и мини-отчёт для конца операции
    if [ "$context" = "end_operation" ]; then
        echo -e "${BLUE}=== MiniStack ===${NC}"
        echo -e "[${timestamp_file}] === MiniStack ===" >> "$LOG_FILE"
        local success_count="${SUCCESS_COUNT:-0}"
        local error_count="${ERROR_COUNT:-0}"
        local operation_name="$4"
        echo -e "${BLUE}INFO - $operation_name: $success_count успехов, $error_count ошибок${NC}"
        echo -e "[${timestamp_file}] INFO - $operation_name: $success_count успехов, $error_count ошибок" >> "$LOG_FILE"
        if [ "$success_count" -gt 0 ]; then
            RANDOM_INDEX=$((RANDOM % ${#FUNNY_MESSAGES[@]}))
            RANDOM_MESSAGE="${FUNNY_MESSAGES[$RANDOM_INDEX]}"
            echo -e "${YELLOW}$RANDOM_MESSAGE${NC}"
            echo -e "[${timestamp_file}] INFO - $RANDOM_MESSAGE" >> "$LOG_FILE"
        fi
    fi
}

# Инициализация директорий и файлов для credentials и логов
init_credentials() {
    mkdir -p "$CREDENTIALS_DIR" /var/log
    touch "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    chown root:root "$CREDENTIALS_DIR" "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    chmod 700 "$CREDENTIALS_DIR"
    chmod 600 "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    log_message "info" "Директории и файлы credentials инициализированы"
}

# Очистка временных файлов и базы данных для домена при ошибке
cleanup_site() {
    local domain="$1"
    log_message "info" "Очищены временные файлы и база для $domain"
    WEB_ROOT="/var/www/$domain"
    CONFIG_FILE="/etc/nginx/sites-available/$domain"
    ENABLED_FILE="/etc/nginx/sites-enabled/$domain"
    DB_NAME=$(domain_to_db_name "$domain")
    DB_ROOT_PASS=$(get_db_root_pass)
    export MYSQL_PWD="$DB_ROOT_PASS"
    [ -f "$ENABLED_FILE" ] && rm -f "$ENABLED_FILE"
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    [ -d "$WEB_ROOT" ] && rm -rf "$WEB_ROOT"
    # Используем файл конфигурации, если он доступен, иначе MYSQL_PWD
    if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
        mysql --defaults-file="$MYSQL_CONFIG_FILE" -u root -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null
        mysql --defaults-file="$MYSQL_CONFIG_FILE" -u root -e "DROP USER IF EXISTS 'wp_$DB_NAME'@'localhost';" 2>/dev/null
    else
        mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null
        mysql -u root -e "DROP USER IF EXISTS 'wp_$DB_NAME'@'localhost';" 2>/dev/null
    fi
    if grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        sed -i "/Site: $domain/,/-------------------/d" "$SITE_CREDENTIALS" 2>/dev/null
    fi
}

# Удаление логов старше 30 дней
clean_old_logs() {
    if [ -f "$LOG_FILE" ]; then
        if find "$LOG_FILE" -mtime +30 -exec rm -f {} \; 2>/dev/null; then
            if [ ! -f "$LOG_FILE" ]; then
                log_message "info" "Лог старше 30 дней удалён, создан новый"
                touch "$LOG_FILE"
                chmod 600 "$LOG_FILE"
            fi
        fi
    fi
}

# Преобразование домена в Punycode
convert_to_punycode() {
    local domain="$1"
    if command -v idn2 >/dev/null 2>&1; then
        punycode_domain=$(idn2 "$domain" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$punycode_domain" ]; then
            echo "$punycode_domain"
        else
            echo "$domain"
        fi
    else
        log_message "warning" "Утилита idn2 не установлена, домен $domain использован без преобразования"
        echo "$domain"
    fi
}

clean_domain() {
    local domain=$1
    domain=$(echo "$domain" | sed -E 's|^https?://||; s|://||; s|/+$||')
    echo "$domain"
}

# Преобразование домена в имя базы данных (замена всех спецсимволов и дефисов на подчеркивания)
domain_to_db_name() {
    local domain=$1
    local db_name
    # Заменяем все не-буквенно-цифровые символы (кроме подчеркивания) на подчеркивания
    # Это включает точки, дефисы и другие спецсимволы
    db_name=$(echo "$domain" | sed 's/[^a-zA-Z0-9_]/_/g')
    # Удаляем множественные подчеркивания
    db_name=$(echo "$db_name" | sed 's/__*/_/g')
    # Удаляем подчеркивания в начале и конце
    db_name=$(echo "$db_name" | sed 's/^_\|_$//g')
    echo "$db_name"
}

get_db_root_pass() {
    if [ -f "$MARIADB_CREDENTIALS" ]; then
        # Извлекаем пароль: берем строку после "MariaDB Root Password: " до конца строки
        DB_ROOT_PASS=$(grep "^MariaDB Root Password:" "$MARIADB_CREDENTIALS" | sed 's/^MariaDB Root Password: //' | sed 's/[[:space:]]*$//' | tr -d '\n\r')
        if [ -z "$DB_ROOT_PASS" ]; then
            log_message "error" "Пароль root MariaDB не найден в $MARIADB_CREDENTIALS"
            exit 1
        fi
    else
        log_message "error" "Файл $MARIADB_CREDENTIALS не существует"
        exit 1
    fi
    echo "$DB_ROOT_PASS"
}

# Проверка и обновление пароля root MySQL, если он не совпадает
verify_and_fix_db_password() {
    local stored_pass=$(get_db_root_pass)
    export MYSQL_PWD="$stored_pass"
    
    # Проверяем, работает ли сохраненный пароль
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        return 0
    fi
    
    log_message "warning" "Сохраненный пароль root не работает. Попытка подключения без пароля..."
    
    # Пробуем подключиться без пароля (если MariaDB только что установлена)
    unset MYSQL_PWD
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        log_message "info" "Подключение без пароля успешно. Устанавливаем новый пароль..."
        # Генерируем новый пароль
        local new_pass=$(openssl rand -base64 12)
        if mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_pass';" 2>&1; then
            export MYSQL_PWD="$new_pass"
            if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
                # Сохраняем новый пароль
                echo "MariaDB Root Password: $new_pass" > "$MARIADB_CREDENTIALS"
                chmod 600 "$MARIADB_CREDENTIALS"
                log_message "success" "Пароль root обновлен и сохранен"
                return 0
            fi
        fi
    fi
    
    # Если все предыдущие попытки не удались, пробуем сбросить пароль через безопасный режим
    log_message "warning" "Попытка сброса пароля через безопасный режим MariaDB..."
    if reset_mariadb_password; then
        return 0
    fi
    
    log_message "error" "Не удалось установить/проверить пароль root MySQL"
    log_message "error" "Попробуйте выполнить вручную: sudo mysql -u root"
    log_message "error" "Затем выполните: ALTER USER 'root'@'localhost' IDENTIFIED BY 'ваш_пароль';"
    return 1
}

# Сброс пароля root MariaDB через безопасный режим (--skip-grant-tables)
reset_mariadb_password() {
    log_message "info" "Начинаем сброс пароля root MariaDB через безопасный режим..."
    
    # Проверяем, что мы запущены от root
    if [ "$EUID" -ne 0 ]; then
        log_message "error" "Сброс пароля требует прав root. Запустите скрипт с sudo."
        return 1
    fi
    
    # Проверяем, что MariaDB установлена (несколько способов проверки)
    MARIADB_INSTALLED=0
    if systemctl list-unit-files | grep -qE "(mariadb|mysql)\.service"; then
        MARIADB_INSTALLED=1
    elif command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1; then
        MARIADB_INSTALLED=1
    elif dpkg -l | grep -qE "(mariadb-server|mysql-server)"; then
        MARIADB_INSTALLED=1
    elif systemctl status mariadb >/dev/null 2>&1 || systemctl status mysql >/dev/null 2>&1; then
        MARIADB_INSTALLED=1
    fi
    
    if [ "$MARIADB_INSTALLED" -eq 0 ]; then
        log_message "error" "MariaDB/MySQL не установлена или служба не найдена"
        log_message "info" "Попробуйте установить MariaDB: apt install -y mariadb-server mariadb-client"
        return 1
    fi
    
    # Определяем имя службы (mariadb или mysql)
    local service_name="mariadb"
    if systemctl list-unit-files | grep -q mysql.service && ! systemctl list-unit-files | grep -q mariadb.service; then
        service_name="mysql"
    elif ! systemctl list-unit-files | grep -q mariadb.service && ! systemctl list-unit-files | grep -q mysql.service; then
        # Если служба еще не зарегистрирована, проверяем через systemctl status
        if systemctl status mysql >/dev/null 2>&1 && ! systemctl status mariadb >/dev/null 2>&1; then
            service_name="mysql"
        fi
    fi
    
    log_message "info" "Останавливаем $service_name..."
    if ! systemctl stop "$service_name" 2>&1; then
        log_message "error" "Не удалось остановить $service_name"
        return 1
    fi
    
    # Ждем немного, чтобы служба точно остановилась
    sleep 2
    
    log_message "info" "Запускаем $service_name в безопасном режиме (--skip-grant-tables)..."
    
    # Используем mysqld_safe для запуска в безопасном режиме
    local safe_pid=""
    local override_dir=""
    
    if command -v mysqld_safe >/dev/null 2>&1; then
        log_message "info" "Используем mysqld_safe для запуска в безопасном режиме..."
        mysqld_safe --skip-grant-tables --skip-networking >/dev/null 2>&1 &
        safe_pid=$!
    else
        # Альтернативный способ: создаем временный systemd override
        log_message "info" "Используем systemd для запуска в безопасном режиме..."
        override_dir="/etc/systemd/system/${service_name}.service.d"
        mkdir -p "$override_dir"
        cat > "$override_dir/reset-password.conf" <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/mysqld --skip-grant-tables --skip-networking
EOF
        systemctl daemon-reload
        systemctl start "$service_name" 2>&1
        safe_pid=$(systemctl show -p MainPID "$service_name" --value 2>/dev/null || echo "")
    fi
    
    # Ждем, пока MariaDB запустится
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_message "error" "Не удалось запустить MariaDB в безопасном режиме"
        if [ -n "$safe_pid" ] && [ "$safe_pid" != "0" ]; then
            kill "$safe_pid" 2>/dev/null
        fi
        if [ -n "$override_dir" ] && [ -d "$override_dir" ]; then
            rm -rf "$override_dir"
            systemctl daemon-reload
        fi
        systemctl start "$service_name" 2>/dev/null
        return 1
    fi
    
    log_message "info" "MariaDB запущена в безопасном режиме. Устанавливаем новый пароль..."
    
    # Генерируем новый пароль
    local new_pass=$(openssl rand -base64 12)
    
    # Обновляем пароль (в безопасном режиме нужно использовать UPDATE вместо ALTER USER)
    if mysql -u root <<EOF 2>&1; then
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_pass';
FLUSH PRIVILEGES;
EOF
        log_message "success" "Пароль обновлен в безопасном режиме"
    else
        log_message "error" "Не удалось обновить пароль в безопасном режиме"
        if [ -n "$safe_pid" ] && [ "$safe_pid" != "0" ]; then
            kill "$safe_pid" 2>/dev/null
        fi
        if [ -n "$override_dir" ] && [ -d "$override_dir" ]; then
            rm -rf "$override_dir"
            systemctl daemon-reload
        fi
        systemctl start "$service_name" 2>/dev/null
        return 1
    fi
    
    # Останавливаем безопасный режим
    log_message "info" "Останавливаем безопасный режим..."
    if [ -n "$safe_pid" ] && [ "$safe_pid" != "0" ]; then
        kill "$safe_pid" 2>/dev/null
    fi
    systemctl stop "$service_name" 2>/dev/null
    sleep 2
    
    # Удаляем временные конфигурации
    if [ -n "$override_dir" ] && [ -d "$override_dir" ]; then
        rm -rf "$override_dir"
        systemctl daemon-reload
    fi
    
    # Запускаем MariaDB в обычном режиме
    log_message "info" "Запускаем $service_name в обычном режиме..."
    if ! systemctl start "$service_name" 2>&1; then
        log_message "error" "Не удалось запустить $service_name в обычном режиме"
        return 1
    fi
    
    # Ждем, пока MariaDB запустится
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if systemctl is-active --quiet "$service_name"; then
            break
        fi
        sleep 1
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_message "error" "MariaDB не запустилась после сброса пароля"
        return 1
    fi
    
    # Проверяем новый пароль
    log_message "info" "Проверяем новый пароль..."
    export MYSQL_PWD="$new_pass"
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        # Сохраняем новый пароль
        mkdir -p "$CREDENTIALS_DIR"
        echo "MariaDB Root Password: $new_pass" > "$MARIADB_CREDENTIALS"
        chmod 600 "$MARIADB_CREDENTIALS"
        log_message "success" "Пароль root MariaDB успешно сброшен и сохранен"
        return 0
    else
        log_message "error" "Новый пароль не работает после сброса"
        return 1
    fi
}

# Создание временного файла конфигурации MySQL для безопасной передачи пароля
create_mysql_config() {
    local password="$1"
    local config_file="/tmp/.my.cnf.$$"
    cat > "$config_file" <<EOF
[client]
user=root
password=$password
EOF
    chmod 600 "$config_file"
    echo "$config_file"
}

check_site_exists() {
    local domain=$1
    if [ -f "/etc/nginx/sites-available/$domain" ] || [ -d "/var/www/$domain" ] || grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        log_message "error" "Сайт $domain уже существует"
        return 1
    fi
    return 0
}

check_site_not_exists() {
    local domain=$1
    if [ ! -f "/etc/nginx/sites-available/$domain" ] && [ ! -d "/var/www/$domain" ] && ! grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        log_message "error" "Домен $domain уже удалён"
        return 1
    fi
    return 0
}

check_site_availability() {
    local domain=$1
    if curl -s https://$domain | grep -q "MiniStack CLI"; then
        log_message "info" "Сайт $domain доступен по HTTPS"
        return 0
    elif curl -s http://$domain | grep -q "MiniStack CLI"; then
        log_message "info" "Сайт $domain доступен по HTTP"
        return 0
    else
        log_message "error" "Сайт $domain недоступен ни по HTTPS, ни по HTTP"
        return 1
    fi
}

check_package() {
    local package=$1
    if dpkg -l "$package" >/dev/null 2>&1; then
        log_message "success" "Пакет $package установлен"
        return 0
    else
        log_message "error" "Пакет $package не установлен"
        exit 1
    fi
}

check_service() {
    local service=$1
    if systemctl is-active "$service" >/dev/null; then
        log_message "success" "Служба $service активна"
        return 0
    else
        log_message "error" "Служба $service не активна"
        exit 1
    fi
}

check_php() {
    local version=$1
    if php${version} --version >/dev/null 2>&1; then
        log_message "success" "PHP $version установлен"
        return 0
    else
        log_message "error" "PHP $version не установлен"
        exit 1
    fi
}

check_wp_cli() {
    if wp --version --allow-root >/dev/null 2>&1; then
        log_message "success" "wp-cli установлен"
        return 0
    else
        log_message "error" "wp-cli не установлен"
        exit 1
    fi
}
