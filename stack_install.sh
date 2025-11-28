# stack_install.sh - Команда для установки LEMP-стека в MiniStack CLI
# Версия 1.0.31

install_stack() {
    . /usr/local/lib/minStack/utils.sh
    clean_old_logs
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --install: $@. Используйте без флагов"
        exit 1
    fi
    welcome
    log_message "info" "Проверяем установку LEMP-стека..." "start_operation"
    init_credentials
    if check_stack_installed; then
        SUCCESS_COUNT=1
        ERROR_COUNT=0
        log_message "info" "LEMP-стек уже установлен" "end_operation" "Установка стека завершена"
        exit 0
    fi
    log_message "info" "Запускаем установку LEMP-стека..."
    export DEBIAN_FRONTEND=noninteractive
    apt update && apt upgrade -y
    log_message "success" "Система обновлена!"
    setup_php_repository
    apt install -y nginx libidn2-0 idn2
    check_package nginx
    check_package libidn2-0
    systemctl enable nginx
    systemctl start nginx
    check_service nginx
    mkdir -p /etc/ssl/private /etc/ssl/certs
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/CN=localhost" || { log_message "error" "Не удалось создать самоподписанный сертификат"; exit 1; }
    chmod 600 /etc/ssl/private/nginx-selfsigned.key
    log_message "success" "Самоподписанный SSL-сертификат создан!"
    rm -rf /var/www/html/*
    echo "MiniStack CLI" > /var/www/html/index.html
    chmod 644 /var/www/html/index.html
    log_message "success" "Дефолтный index.html создан!"
    cat > /etc/nginx/sites-available/default <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html;
}
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    root /var/www/html;
    index index.html;
}
EOL
    nginx -t && systemctl reload nginx
    log_message "success" "Дефолтный конфиг Nginx настроен!"
    # Сначала устанавливаем MariaDB
    apt install -y mariadb-server mariadb-client
    check_package mariadb-server
    systemctl enable mariadb
    systemctl start mariadb
    check_service mariadb
    
    # Теперь проверяем/устанавливаем пароль
    PASSWORD_WAS_RESET=0
    if [ -f "$MARIADB_CREDENTIALS" ] && [ -s "$MARIADB_CREDENTIALS" ]; then
        log_message "info" "Файл с паролем MariaDB уже существует. Проверяем существующий пароль..."
        # Проверяем, есть ли в файле пароль
        if grep -q "^MariaDB Root Password:" "$MARIADB_CREDENTIALS"; then
            DB_ROOT_PASS=$(grep "^MariaDB Root Password:" "$MARIADB_CREDENTIALS" | sed 's/^MariaDB Root Password: //' | sed 's/[[:space:]]*$//' | tr -d '\n\r')
        fi
        
        # Если пароль найден и не пустой, пробуем его использовать
        if [ -n "$DB_ROOT_PASS" ]; then
            export MYSQL_PWD="$DB_ROOT_PASS"
            # Проверяем, работает ли существующий пароль
            if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
                log_message "success" "Существующий пароль root MariaDB работает. Используем его."
                # Пароль работает, не будем его менять
            else
                log_message "warning" "Существующий пароль не работает. Сбрасываем пароль..."
                # Сбрасываем пароль (функция сама сгенерирует новый и сохранит в файл)
                if ! reset_mariadb_password; then
                    log_message "error" "Не удалось сбросить пароль root для MariaDB"
                    exit 1
                fi
                # После сброса получаем новый пароль из файла
                DB_ROOT_PASS=$(get_db_root_pass)
                PASSWORD_WAS_RESET=1
            fi
        else
            # Файл существует, но пароль пустой или отсутствует
            log_message "warning" "Файл с паролем существует, но пароль пустой. Генерируем новый пароль..."
            DB_ROOT_PASS=$(openssl rand -base64 12)
        fi
    else
        # Файла с паролем нет, генерируем новый
        log_message "info" "Файл с паролем MariaDB не найден. Генерируем новый пароль..."
        DB_ROOT_PASS=$(openssl rand -base64 12)
    fi
    
    # Пробуем подключиться без пароля (для свежеустановленной MariaDB)
    log_message "info" "Проверяем подключение к MariaDB..."
    unset MYSQL_PWD
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        # Подключение без пароля работает, устанавливаем пароль
        log_message "info" "Подключение без пароля успешно. Устанавливаем пароль root..."
        if ! mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';" 2>&1; then
            log_message "error" "Не удалось установить пароль root для MariaDB"
            exit 1
        fi
    else
        # Если не получается подключиться без пароля, проверяем существующий пароль
        export MYSQL_PWD="$DB_ROOT_PASS"
        if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            log_message "info" "Подключение с существующим паролем успешно."
        else
            # Используем сброс пароля
            log_message "warning" "Не удалось подключиться к MariaDB. Используем сброс пароля..."
            if ! reset_mariadb_password; then
                log_message "error" "Не удалось установить пароль root для MariaDB через сброс"
                exit 1
            fi
            # После сброса пароль уже установлен, получаем его из файла
            DB_ROOT_PASS=$(get_db_root_pass)
            PASSWORD_WAS_RESET=1
        fi
    fi
    
    # Проверяем, что пароль действительно установлен
    export MYSQL_PWD="$DB_ROOT_PASS"
    if ! mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        log_message "error" "Пароль root не установлен корректно в MariaDB"
        exit 1
    fi
    
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
    mysql -u root -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
    log_message "success" "MariaDB настроена!"
    
    # Сохраняем пароль - проверяем все возможные случаи
    mkdir -p "$CREDENTIALS_DIR"
    
    # Если пароль был сброшен, файл уже обновлен функцией reset_mariadb_password
    if [ "$PASSWORD_WAS_RESET" -eq 1 ]; then
        log_message "info" "Пароль root MariaDB был сброшен и сохранен"
    # Проверяем, нужно ли сохранять пароль
    elif [ ! -f "$MARIADB_CREDENTIALS" ] || [ ! -s "$MARIADB_CREDENTIALS" ]; then
        # Файл не существует или пустой - сохраняем пароль
        echo "MariaDB Root Password: $DB_ROOT_PASS" > "$MARIADB_CREDENTIALS"
        chmod 600 "$MARIADB_CREDENTIALS"
        log_message "success" "Пароль root MariaDB сохранен в $MARIADB_CREDENTIALS"
    elif ! grep -q "^MariaDB Root Password:" "$MARIADB_CREDENTIALS" 2>/dev/null; then
        # Файл существует, но пароля в нем нет - сохраняем пароль
        echo "MariaDB Root Password: $DB_ROOT_PASS" > "$MARIADB_CREDENTIALS"
        chmod 600 "$MARIADB_CREDENTIALS"
        log_message "success" "Пароль root MariaDB записан в файл $MARIADB_CREDENTIALS"
    else
        # Файл существует и содержит пароль - проверяем, совпадает ли он с текущим
        local saved_pass=$(get_db_root_pass 2>/dev/null || echo "")
        if [ -z "$saved_pass" ] || [ "$saved_pass" != "$DB_ROOT_PASS" ]; then
            # Пароль в файле не совпадает с текущим рабочим паролем - обновляем файл
            echo "MariaDB Root Password: $DB_ROOT_PASS" > "$MARIADB_CREDENTIALS"
            chmod 600 "$MARIADB_CREDENTIALS"
            log_message "success" "Пароль root MariaDB обновлен в $MARIADB_CREDENTIALS"
        else
            # Файл содержит правильный пароль - не трогаем его
            log_message "info" "Пароль root MariaDB уже сохранен и работает, файл не изменен"
        fi
    fi
    for version in "${PHP_VERSIONS[@]}"; do
        apt install -y php${version} php${version}-fpm php${version}-mysql php${version}-mbstring php${version}-xml php${version}-curl php${version}-zip
        check_php "$version"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 256M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/post_max_size = .*/post_max_size = 256M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/${version}/fpm/php.ini
        sed -i 's/max_input_time = .*/max_input_time = 300/' /etc/php/${version}/fpm/php.ini
        sed -i 's/expose_php = On/expose_php = Off/' /etc/php/${version}/fpm/php.ini
        systemctl enable php${version}-fpm
        systemctl start php${version}-fpm
        check_service php${version}-fpm
    done
    log_message "success" "PHP настроен!"
    apt install -y certbot python3-certbot-nginx
    check_package certbot
    wget -qO /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /usr/local/bin/wp
    check_wp_cli
    mkdir -p /etc/nginx/common
    cat > /etc/nginx/common/security_headers.conf <<EOL
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
add_header Content-Security-Policy "default-src 'self' https: data: blob:; img-src 'self' https: data: blob:; script-src 'self' https: 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' https: 'unsafe-inline'; font-src 'self' https: data:; connect-src 'self' https: wss:; frame-src https: *.youtube.com *.vimeo.com blob:;" always;
EOL
    log_message "success" "Безопасные заголовки настроены!"
    clean_headers
    final_check_and_restart
    log_message "success" "LEMP-стек установлен!"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Установка стека завершена" "end_operation" "Установка стека завершена"
}
