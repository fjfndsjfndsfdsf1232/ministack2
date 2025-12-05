# site_bulk_create_multisite.sh - Команда для массового создания сайтов в WordPress Multisite
# Версия 2.1.0 - Исправлено для полной работоспособности domain mapping с несколькими доменами

bulk_create_sites_multisite() {
    clean_old_logs
    SKIP_AVAILABILITY_CHECK=0
    if [ "$1" = "--skip-availability-check" ]; then
        SKIP_AVAILABILITY_CHECK=1
        shift
    fi
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --bulk-multisite: $@. Используйте без флагов или --skip-availability-check"
        exit 1
    fi
    log_message "info" "Запускаем массовый деплой сайтов в WordPress Multisite..." "start_operation"
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
        log_message "error" "Нет валидных доменов для деплоя"
        exit 1
    fi

    while true; do
        echo -e "${YELLOW}Выберите версию PHP:${NC}"
        for i in "${!PHP_VERSIONS[@]}"; do
            echo -e "${YELLOW}$((i+1)).${NC} PHP ${PHP_VERSIONS[i]}"
        done
        echo -e "${YELLOW}Введите номер (1-${#PHP_VERSIONS[@]}):${NC}"
        read -r php_choice
        if [[ "$php_choice" =~ ^[1-5]$ ]]; then
            PHP_VERSION="${PHP_VERSIONS[$((php_choice-1))]}"
            PHP_FLAG="--php${PHP_VERSION//./}"
            log_message "info" "Выбрана версия PHP: $PHP_VERSION"
            break
        else
            log_message "error" "Неверный выбор PHP. Допустимые значения: 1-${#PHP_VERSIONS[@]}"
            exit 1
        fi
    done

    while true; do
        echo -e "${YELLOW}Выберите настройку редиректа:${NC}"
        echo -e "${YELLOW}1.${NC} Редирект на www"
        echo -e "${YELLOW}2.${NC} Редирект с www на домен"
        echo -e "${YELLOW}3.${NC} Без редиректа (оба варианта)"
        echo -e "${YELLOW}Введите номер (1-3):${NC}"
        read -r redirect_choice
        case $redirect_choice in
            1) REDIRECT_MODE="yes-www"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            2) REDIRECT_MODE="no-www"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            3) REDIRECT_MODE="none"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            *) log_message "error" "Неверный выбор редиректа. Допустимые значения: 1-3"; exit 1 ;;
        esac
    done

    while true; do
        echo -e "${YELLOW}Выпускать SSL-сертификаты для сайтов?${NC}"
        echo -e "${YELLOW}1.${NC} Let's Encrypt"
        echo -e "${YELLOW}2.${NC} Самоподписанный (OpenSSL)"
        echo -e "${YELLOW}3.${NC} Без SSL"
        echo -e "${YELLOW}Введите номер (1-3):${NC}"
        read -r ssl_choice
        case $ssl_choice in
            1) SSL_ENABLED="yes"; SSL_TYPE="--letsencrypt"; log_message "info" "Выпуск SSL: $SSL_TYPE"; break ;;
            2) SSL_ENABLED="yes"; SSL_TYPE="--selfsigned"; log_message "info" "Выпуск SSL: $SSL_TYPE"; break ;;
            3) SSL_ENABLED="no"; SSL_TYPE=""; log_message "info" "Выпуск SSL: отключен"; break ;;
            *) log_message "error" "Неверный выбор для SSL. Допустимые значения: 1-3"; exit 1 ;;
        esac
    done

    # Проверка и исправление пароля MySQL перед началом массового деплоя
    if ! verify_and_fix_db_password; then
        log_message "error" "Не удалось проверить/исправить пароль root MySQL"
        exit 1
    fi
    
    DB_ROOT_PASS=$(get_db_root_pass)
    export MYSQL_PWD="$DB_ROOT_PASS"
    
    # Проверяем подключение к MySQL
    MYSQL_TEST_ERROR=$(mysql -u root -e "SELECT 1;" 2>&1)
    if [ $? -ne 0 ]; then
        # Пробуем использовать файл конфигурации как запасной вариант
        MYSQL_CONFIG=$(create_mysql_config "$DB_ROOT_PASS")
        MYSQL_TEST_ERROR=$(mysql --defaults-file="$MYSQL_CONFIG" -u root -e "SELECT 1;" 2>&1)
        if [ $? -eq 0 ]; then
            export MYSQL_CONFIG_FILE="$MYSQL_CONFIG"
            log_message "info" "Используется файл конфигурации MySQL для подключения"
        else
            rm -f "$MYSQL_CONFIG"
            log_message "error" "Не удалось подключиться к MySQL: $MYSQL_TEST_ERROR"
            log_message "error" "Проверьте пароль в $MARIADB_CREDENTIALS и убедитесь, что MariaDB запущена"
            log_message "info" "Попробуйте выполнить вручную: mysql -u root -p"
            exit 1
        fi
    else
        unset MYSQL_CONFIG_FILE
    fi
    log_message "success" "Подключение к MySQL успешно"

    # ОПТИМИЗАЦИЯ: Инициализация credentials один раз в начале
    init_credentials
    
    # Проверяем наличие wp-cli
    if ! command -v wp >/dev/null 2>&1; then
        log_message "error" "wp-cli не установлен. Установите wp-cli для работы с WordPress Multisite"
        exit 1
    fi
    check_wp_cli
    
    # Определяем главный домен (первый в списке)
    MAIN_DOMAIN="${VALID_DOMAINS[0]}"
    MAIN_ORIGINAL_DOMAIN="${ORIGINAL_DOMAINS[0]}"
    
    # Проверяем, не существует ли уже multisite установка
    MULTISITE_ROOT="/var/www/multisite"
    if [ -d "$MULTISITE_ROOT" ] && [ -f "$MULTISITE_ROOT/wp-config.php" ]; then
        log_message "info" "Найдена существующая установка WordPress Multisite в $MULTISITE_ROOT"
        read -p "Использовать существующую установку? (y/n): " use_existing
        if [ "$use_existing" != "y" ] && [ "$use_existing" != "Y" ]; then
            log_message "info" "Создаём новую установку WordPress Multisite"
            rm -rf "$MULTISITE_ROOT"
        else
            log_message "info" "Используем существующую установку WordPress Multisite"
        fi
    fi
    
    # Скачиваем WordPress один раз для всех сайтов
    WP_CACHE_DIR="/tmp/wordpress-cache"
    if [ ! -f "$WP_CACHE_DIR/latest.tar.gz" ]; then
        log_message "info" "Скачиваем WordPress в кеш (один раз для всех сайтов)..."
        mkdir -p "$WP_CACHE_DIR"
        wget -qO "$WP_CACHE_DIR/latest.tar.gz" https://wordpress.org/latest.tar.gz
        if [ $? -eq 0 ]; then
            log_message "success" "WordPress закеширован для массового деплоя"
        else
            log_message "error" "Не удалось скачать WordPress"
            exit 1
        fi
    else
        log_message "info" "Используется закешированный WordPress"
    fi
    
    # Создаём директорию для multisite, если её нет
    if [ ! -d "$MULTISITE_ROOT" ]; then
        log_message "info" "Создаём установку WordPress Multisite..."
        mkdir -p "$MULTISITE_ROOT"
        tar xzf "$WP_CACHE_DIR/latest.tar.gz" -C "$MULTISITE_ROOT" --strip-components=1
        chown -R www-data:www-data "$MULTISITE_ROOT"
        mkdir -p "$MULTISITE_ROOT/wp-content/uploads"
        chown -R www-data:www-data "$MULTISITE_ROOT/wp-content/uploads"
        chmod -R 755 "$MULTISITE_ROOT/wp-content/uploads"
        log_message "success" "WordPress распакован в $MULTISITE_ROOT"
    fi
    
    # Настройка базы данных для multisite
    MULTISITE_DB_NAME="wp_multisite"
    MULTISITE_DB_USER="wp_multisite"
    MULTISITE_DB_PASS=$(openssl rand -base64 12)
    
    # Используем файл конфигурации, если он создан, иначе используем MYSQL_PWD
    if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
        MYSQL_CMD="mysql --defaults-file=$MYSQL_CONFIG_FILE -u root"
    else
        MYSQL_CMD="mysql -u root"
    fi
    
    # Создаём базу данных для multisite, если её нет
    if ! $MYSQL_CMD -e "USE $MULTISITE_DB_NAME;" 2>/dev/null; then
        log_message "info" "Создаём базу данных для WordPress Multisite..."
        MYSQL_ERROR=$($MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS $MULTISITE_DB_NAME;" 2>&1)
        if [ $? -ne 0 ]; then
            log_message "error" "Не удалось создать базу данных $MULTISITE_DB_NAME: $MYSQL_ERROR"
            exit 1
        fi
        
        USER_EXISTS=$($MYSQL_CMD -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User='$MULTISITE_DB_USER' AND Host='localhost');" 2>/dev/null | tail -n 1)
        if [ "$USER_EXISTS" = "1" ]; then
            MYSQL_ERROR=$($MYSQL_CMD -e "ALTER USER '$MULTISITE_DB_USER'@'localhost' IDENTIFIED BY '$MULTISITE_DB_PASS';" 2>&1)
        else
            MYSQL_ERROR=$($MYSQL_CMD -e "CREATE USER '$MULTISITE_DB_USER'@'localhost' IDENTIFIED BY '$MULTISITE_DB_PASS';" 2>&1)
        fi
        
        if [ $? -ne 0 ]; then
            log_message "error" "Не удалось создать/обновить пользователя $MULTISITE_DB_USER: $MYSQL_ERROR"
            exit 1
        fi
        
        MYSQL_ERROR=$($MYSQL_CMD -e "GRANT ALL PRIVILEGES ON $MULTISITE_DB_NAME.* TO '$MULTISITE_DB_USER'@'localhost';" 2>&1)
        if [ $? -ne 0 ]; then
            log_message "error" "Не удалось выдать привилегии для пользователя $MULTISITE_DB_USER: $MYSQL_ERROR"
            exit 1
        fi
        
        MYSQL_ERROR=$($MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>&1)
        if [ $? -ne 0 ]; then
            log_message "error" "Не удалось обновить привилегии: $MYSQL_ERROR"
            exit 1
        fi
        
        log_message "success" "База данных $MULTISITE_DB_NAME создана"
    else
        log_message "info" "База данных $MULTISITE_DB_NAME уже существует"
    fi
    
    # Настраиваем wp-config.php для multisite, если WordPress ещё не установлен
    cd "$MULTISITE_ROOT"
    if [ ! -f "$MULTISITE_ROOT/wp-config.php" ]; then
        log_message "info" "Создаём wp-config.php для WordPress Multisite..."
        sudo -u www-data wp config create --dbname="$MULTISITE_DB_NAME" --dbuser="$MULTISITE_DB_USER" --dbpass="$MULTISITE_DB_PASS" --dbhost=localhost --allow-root >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_message "error" "wp-config.php не создан"
            exit 1
        fi
        
        # Добавляем поддержку multisite перед комментарием "That's all" (только если еще не определена)
        if ! grep -q "define.*WP_ALLOW_MULTISITE" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
            sed -i "/\/\* That's all, stop editing/i\\
define('WP_ALLOW_MULTISITE', true);" "$MULTISITE_ROOT/wp-config.php"
        fi
        
        # Добавляем поддержку HTTPS через прокси в начало файла (только если еще не добавлено)
        if ! grep -q "HTTP_X_FORWARDED_PROTO" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
            sed -i "1a if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { \$_SERVER['HTTPS'] = 'on'; }" "$MULTISITE_ROOT/wp-config.php"
        fi
        
        log_message "success" "wp-config.php создан с поддержкой multisite"
    fi
    
    # Устанавливаем WordPress multisite, если ещё не установлен
    if ! sudo -u www-data wp core is-installed --allow-root >/dev/null 2>&1; then
        log_message "info" "Устанавливаем WordPress Multisite на главном домене $MAIN_ORIGINAL_DOMAIN..."
        
        WP_ADMIN_USER="admin_$(openssl rand -hex 4)"
        WP_ADMIN_PASS=$(openssl rand -base64 12)
        WP_ADMIN_EMAIL="admin@$MAIN_ORIGINAL_DOMAIN"
        WP_SITE_TITLE="$MAIN_ORIGINAL_DOMAIN Network"
        
        # Устанавливаем WordPress Multisite напрямую (без предварительной установки обычного WordPress)
        # Используем --subdomains=false для подкаталогов (но мы настроим domain mapping)
        sudo -u www-data wp core multisite-install \
            --url="http://$MAIN_DOMAIN" \
            --title="$WP_SITE_TITLE" \
            --admin_user="$WP_ADMIN_USER" \
            --admin_password="$WP_ADMIN_PASS" \
            --admin_email="$WP_ADMIN_EMAIL" \
            --subdomains=false \
            --allow-root >/dev/null 2>&1
        
        if [ $? -ne 0 ]; then
            log_message "error" "WordPress Multisite не установлен"
            exit 1
        fi
        
        # После установки multisite, wp-config.php будет обновлен с константами MULTISITE
        # Добавляем константу SUNRISE для поддержки domain mapping (если её еще нет)
        if ! grep -q "define.*SUNRISE" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
            # Находим место после констант MULTISITE и добавляем SUNRISE
            if grep -q "define.*MULTISITE" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
                sed -i "/define.*MULTISITE/a\\
define('SUNRISE', 'on');" "$MULTISITE_ROOT/wp-config.php"
                log_message "success" "Константа SUNRISE добавлена в wp-config.php для domain mapping"
            fi
        fi
        
        # Создаём файл sunrise.php для domain mapping
        SUNRISE_FILE="$MULTISITE_ROOT/wp-content/sunrise.php"
        if [ ! -f "$SUNRISE_FILE" ]; then
            log_message "info" "Создаём файл sunrise.php для domain mapping..."
            cat > "$SUNRISE_FILE" <<'SUNRISE_EOF'
<?php
/**
 * WordPress Multisite Domain Mapping
 * Этот файл позволяет WordPress Multisite работать с разными доменами
 * 
 * WordPress автоматически использует этот файл для определения сайта по домену
 * когда константа SUNRISE установлена в 'on' в wp-config.php
 */

// Этот файл должен быть пустым или содержать минимальный код
// WordPress Multisite сам обрабатывает domain mapping через таблицу wp_blogs
// Просто наличие этого файла позволяет WordPress загрузить его без ошибок
SUNRISE_EOF
            chown www-data:www-data "$SUNRISE_FILE"
            chmod 644 "$SUNRISE_FILE"
            log_message "success" "Файл sunrise.php создан"
        else
            log_message "info" "Файл sunrise.php уже существует"
        fi
        
        # Обновляем domain главного сайта в базе данных
        if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
            MYSQL_CMD="mysql --defaults-file=$MYSQL_CONFIG_FILE -u root"
        else
            MYSQL_CMD="mysql -u root"
        fi
        
        # Обновляем domain главного сайта в таблице wp_blogs
        $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_blogs SET domain='$MAIN_DOMAIN' WHERE blog_id=1;" 2>/dev/null
        
        # Обновляем опции главного сайта через wp-cli с правильным --url
        sudo -u www-data wp option update home "http://$MAIN_DOMAIN" --url="http://$MAIN_DOMAIN" --allow-root >/dev/null 2>&1
        sudo -u www-data wp option update siteurl "http://$MAIN_DOMAIN" --url="http://$MAIN_DOMAIN" --allow-root >/dev/null 2>&1
        
        # Также обновляем через прямой SQL запрос для надежности
        $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_options SET option_value='http://$MAIN_DOMAIN' WHERE option_name IN ('home', 'siteurl');" 2>/dev/null
        
        # Обновляем wp_site_options для главного сайта (если таблица существует)
        $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_site SET domain='$MAIN_DOMAIN' WHERE id=1;" 2>/dev/null
        
        log_message "success" "WordPress Multisite установлен на главном домене $MAIN_ORIGINAL_DOMAIN"
        log_message "success" "WordPress админ: $WP_ADMIN_USER | $WP_ADMIN_PASS (Email: $WP_ADMIN_EMAIL)"
        
        # Сохраняем credentials главного сайта
        echo "WordPress Multisite Installation" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Main Domain: $MAIN_ORIGINAL_DOMAIN" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Multisite Root: $MULTISITE_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Multisite DB Name: $MULTISITE_DB_NAME" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Multisite DB User: $MULTISITE_DB_USER" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Multisite DB Password: $MULTISITE_DB_PASS" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "WordPress Admin User: $WP_ADMIN_USER" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "WordPress Admin Password: $WP_ADMIN_PASS" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "WordPress Admin Email: $WP_ADMIN_EMAIL" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
    else
        log_message "info" "WordPress Multisite уже установлен"
        
        # Проверяем и обновляем wp-config.php для существующей установки
        # Убеждаемся, что константа SUNRISE присутствует для domain mapping
        if ! grep -q "define.*SUNRISE" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
            if grep -q "define.*MULTISITE" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
                sed -i "/define.*MULTISITE/a\\
define('SUNRISE', 'on');" "$MULTISITE_ROOT/wp-config.php"
                log_message "success" "Константа SUNRISE добавлена в существующий wp-config.php"
            fi
        fi
        
        # Проверяем, что константы MULTISITE правильно настроены
        if ! grep -q "define.*MULTISITE.*true" "$MULTISITE_ROOT/wp-config.php" 2>/dev/null; then
            log_message "warning" "Константа MULTISITE не найдена или не установлена в true"
        fi
        
        # Проверяем наличие файла sunrise.php
        SUNRISE_FILE="$MULTISITE_ROOT/wp-content/sunrise.php"
        if [ ! -f "$SUNRISE_FILE" ]; then
            log_message "info" "Создаём файл sunrise.php для существующей установки..."
            cat > "$SUNRISE_FILE" <<'SUNRISE_EOF'
<?php
/**
 * WordPress Multisite Domain Mapping
 * Этот файл позволяет WordPress Multisite работать с разными доменами
 * 
 * WordPress автоматически использует этот файл для определения сайта по домену
 * когда константа SUNRISE установлена в 'on' в wp-config.php
 */

// Этот файл должен быть пустым или содержать минимальный код
// WordPress Multisite сам обрабатывает domain mapping через таблицу wp_blogs
// Просто наличие этого файла позволяет WordPress загрузить его без ошибок
SUNRISE_EOF
            chown www-data:www-data "$SUNRISE_FILE"
            chmod 644 "$SUNRISE_FILE"
            log_message "success" "Файл sunrise.php создан для существующей установки"
        fi
    fi
    
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    VALID_DOMAINS_COUNT=${#VALID_DOMAINS[@]}
    
    # Обрабатываем все домены
    for i in "${!VALID_DOMAINS[@]}"; do
        domain="${VALID_DOMAINS[$i]}"
        original_domain="${ORIGINAL_DOMAINS[$i]}"
        log_message "info" "Обработка домена $original_domain (Punycode: $domain) [$((i+1))/$VALID_DOMAINS_COUNT]"
        
        # Проверяем, не существует ли уже сайт
        if [ -f "/etc/nginx/sites-available/$domain" ] || grep -q "Site: $original_domain" "$SITE_CREDENTIALS"; then
            log_message "error" "Сайт $original_domain уже существует"
            ((ERROR_COUNT++))
            continue
        fi
        
        # Создаём конфигурацию Nginx для домена (все указывают на одну установку WordPress)
        CONFIG_FILE="/etc/nginx/sites-available/$domain"
        ENABLED_FILE="/etc/nginx/sites-enabled/$domain"
        
        generate_nginx_config "$domain" "$MULTISITE_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "--wp"
        
        # Активируем сайт в Nginx
        ln -sf "$CONFIG_FILE" "$ENABLED_FILE"
        if [ ! -L "$ENABLED_FILE" ]; then
            log_message "error" "Сайт $domain не активирован"
            ((ERROR_COUNT++))
            continue
        fi
        
        # Добавляем сайт в WordPress Multisite (только для дополнительных доменов)
        if [ "$domain" != "$MAIN_DOMAIN" ]; then
            log_message "info" "Добавляем сайт $original_domain в WordPress Multisite..."
            
            # Создаём slug на основе домена (без точек и спецсимволов)
            site_slug=$(echo "$domain" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
            
            # Создаём сайт через wp-cli (без флага --domain, только --slug)
            # Перенаправляем stderr в /dev/null чтобы убрать предупреждения PHP
            SITE_ID=$(sudo -u www-data wp site create \
                --slug="$site_slug" \
                --title="$original_domain" \
                --email="admin@$original_domain" \
                --porcelain \
                --allow-root 2>/dev/null | grep -E '^[0-9]+$' | head -n 1)
            
            # Проверяем, что SITE_ID - это число
            if [ -n "$SITE_ID" ] && [ "$SITE_ID" -gt 0 ] 2>/dev/null; then
                log_message "success" "Сайт $original_domain создан в WordPress Multisite (Site ID: $SITE_ID)"
                
                # Обновляем domain в таблице wp_blogs напрямую в базе данных
                if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
                    MYSQL_CMD="mysql --defaults-file=$MYSQL_CONFIG_FILE -u root"
                else
                    MYSQL_CMD="mysql -u root"
                fi
                
                # Обновляем domain в таблице wp_blogs (это ключевой шаг для работы разных доменов)
                MYSQL_UPDATE_RESULT=$($MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_blogs SET domain='$domain' WHERE blog_id=$SITE_ID;" 2>&1)
                
                if [ $? -eq 0 ]; then
                    log_message "success" "Domain обновлен в базе данных для сайта $original_domain (blog_id=$SITE_ID)"
                else
                    log_message "warning" "Не удалось обновить domain в базе данных: $MYSQL_UPDATE_RESULT"
                fi
                
                # Обновляем опции home и siteurl для нового сайта через прямой SQL запрос
                # Это более надежно, чем через wp-cli, так как wp-cli может выдавать предупреждения
                TABLE_PREFIX="wp_${SITE_ID}_"
                $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE ${TABLE_PREFIX}options SET option_value='http://$domain' WHERE option_name='home';" 2>/dev/null
                $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE ${TABLE_PREFIX}options SET option_value='http://$domain' WHERE option_name='siteurl';" 2>/dev/null
                
                # Также пробуем обновить через wp-cli (перенаправляем stderr чтобы убрать предупреждения)
                TEMP_URL="http://$MAIN_DOMAIN/$site_slug/"
                sudo -u www-data wp option update home "http://$domain" --url="$TEMP_URL" --allow-root 2>/dev/null || true
                sudo -u www-data wp option update siteurl "http://$domain" --url="$TEMP_URL" --allow-root 2>/dev/null || true
                
                log_message "success" "Настройки домена $original_domain обновлены (Site ID: $SITE_ID)"
            else
                log_message "error" "Не удалось создать сайт $original_domain: $SITE_ID"
                ((ERROR_COUNT++))
                continue
            fi
        else
            # Для главного домена обновляем опции и базу данных
            log_message "info" "Обновляем настройки главного домена $original_domain..."
            
            # Обновляем через прямой SQL запрос (более надежно)
            if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
                MYSQL_CMD="mysql --defaults-file=$MYSQL_CONFIG_FILE -u root"
            else
                MYSQL_CMD="mysql -u root"
            fi
            $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_options SET option_value='http://$domain' WHERE option_name IN ('home', 'siteurl');" 2>/dev/null
            $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_blogs SET domain='$domain' WHERE blog_id=1;" 2>/dev/null
            $MYSQL_CMD -D "$MULTISITE_DB_NAME" -e "UPDATE wp_site SET domain='$domain' WHERE id=1;" 2>/dev/null || true
            
            # Также пробуем обновить через wp-cli (перенаправляем stderr чтобы убрать предупреждения)
            sudo -u www-data wp option update home "http://$domain" --url="http://$domain" --allow-root 2>/dev/null || true
            sudo -u www-data wp option update siteurl "http://$domain" --url="http://$domain" --allow-root 2>/dev/null || true
        fi
        
        # Настраиваем SSL, если требуется
        if [ "$SSL_ENABLED" = "yes" ]; then
            if setup_ssl "$domain" "$SSL_TYPE"; then
                log_message "success" "SSL ($SSL_TYPE) установлен для $original_domain"
                # Обновляем опции на HTTPS после установки SSL
                sudo -u www-data wp option update home "https://$domain" --url="$domain" --allow-root >/dev/null 2>&1
                sudo -u www-data wp option update siteurl "https://$domain" --url="$domain" --allow-root >/dev/null 2>&1
            else
                log_message "warning" "Не удалось установить SSL ($SSL_TYPE) для $original_domain"
            fi
        fi
        
        # Сохраняем credentials для сайта
        echo "Site: $original_domain" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Type: WordPress Multisite" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Path: $MULTISITE_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "PHP Version: $PHP_VERSION" >> "$SITE_CREDENTIALS" 2>/dev/null
        if [ "$SSL_ENABLED" = "yes" ]; then
            echo "SSL: Enabled ($SSL_TYPE)" >> "$SITE_CREDENTIALS" 2>/dev/null
        else
            echo "SSL: Disabled" >> "$SITE_CREDENTIALS" 2>/dev/null
        fi
        echo "Redirect: $REDIRECT_MODE" >> "$SITE_CREDENTIALS" 2>/dev/null
        echo "Multisite Network: Yes" >> "$SITE_CREDENTIALS" 2>/dev/null
        if [ "$domain" != "$MAIN_DOMAIN" ] && [ -n "$SITE_ID" ]; then
            echo "Multisite Site ID: $SITE_ID" >> "$SITE_CREDENTIALS" 2>/dev/null
        fi
        echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
        chmod 600 "$SITE_CREDENTIALS" 2>/dev/null
        
        log_message "success" "Домен успешно создан $original_domain"
        ((SUCCESS_COUNT++))
    done
    
    # Проверка конфигурации Nginx один раз в конце
    log_message "info" "Проверяем конфигурацию Nginx..."
    if ! nginx -t >/dev/null 2>&1; then
        log_message "error" "Конфигурация Nginx невалидна после массового деплоя"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        log_message "success" "Конфигурация Nginx валидна"
    fi
    
    # Перезапуск Nginx один раз в конце
    log_message "info" "Перезапускаем Nginx..."
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    check_service nginx
    
    # Очистка временного файла конфигурации MySQL, если он был создан
    if [ -n "$MYSQL_CONFIG_FILE" ] && [ -f "$MYSQL_CONFIG_FILE" ]; then
        rm -f "$MYSQL_CONFIG_FILE"
    fi
    
    log_message "info" "Массовый деплой WordPress Multisite завершён" "end_operation" "Массовый деплой WordPress Multisite завершён"
    log_message "info" "Все сайты используют одну установку WordPress в $MULTISITE_ROOT"
    log_message "info" "Для управления сайтами используйте: sudo -u www-data wp site list --allow-root"
    log_message "info" "Для проверки конкретного сайта: sudo -u www-data wp option get home --url=domain.com --allow-root"
}
