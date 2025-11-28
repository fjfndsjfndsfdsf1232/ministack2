# nginx_utils.sh - Утилиты для работы с Nginx в MiniStack CLI
# Версия 1.0.31

generate_nginx_config() {
    local domain="$1"
    local web_root="$2"
    local php_version="$3"
    local redirect_mode="$4"
    local site_type="$5"
    local config_file="/etc/nginx/sites-available/$domain"
    local php_socket="/run/php/php${php_version}-fpm.sock"

    if [ -z "$domain" ] || [ -z "$web_root" ] || [ -z "$php_version" ]; then
        log_message "error" "Недостаточно параметров для генерации конфига Nginx"
        exit 1
    fi

    log_message "info" "Генерируем конфиг Nginx для $domain..."

    # Базовый конфиг для всех типов сайтов
    cat > "$config_file" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    root $web_root;
    index index.php index.html index.htm;
    include /etc/nginx/common/security_headers.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    # Добавляем редиректы
    case $redirect_mode in
        "yes-www")
            cat > "$config_file" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 http://www.$domain\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name www.$domain;
    root $web_root;
    index index.php index.html index.htm;
    include /etc/nginx/common/security_headers.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL
            ;;
        "no-www")
            cat > "$config_file" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name www.$domain;
    return 301 http://$domain\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root $web_root;
    index index.php index.html index.htm;
    include /etc/nginx/common/security_headers.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL
            ;;
        "none")
            # Конфиг уже создан выше, ничего не меняем
            ;;
        *)
            log_message "error" "Неверный режим редиректа: $redirect_mode"
            exit 1
            ;;
    esac

    # Проверка конфига
    if nginx -t >/dev/null 2>&1; then
        log_message "success" "Конфиг Nginx для $domain создан"
    else
        log_message "error" "Конфиг Nginx для $domain невалиден"
        rm -f "$config_file"
        exit 1
    fi
}
