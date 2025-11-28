#!/bin/bash

# uninstall_minstack.sh - Полное удаление MiniStack CLI
# Версия 1.0.31

set -e

# Цвета для вывода
BLUE='\033[0;38;2;0;255;255m'
GREEN='\033[0;38;2;0;255;0m'
RED='\033[0;38;2;255;0;0m'
YELLOW='\033[0;38;2;255;255;0m'
NC='\033[0m'

echo -e "${BLUE}=== MiniStack CLI Uninstall ===${NC}"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен с правами root (используйте sudo)${NC}"
    exit 1
fi

# Определяем режим удаления
# По умолчанию удаляем приложения (как запросил пользователь)
REMOVE_DATA=0
REMOVE_APPS=1
KEEP_APPS=0

for arg in "$@"; do
    if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
        REMOVE_DATA=1
    fi
    if [ "$arg" = "--keep-apps" ] || [ "$arg" = "-k" ]; then
        REMOVE_APPS=0
        KEEP_APPS=1
    fi
    if [ "$arg" = "--all" ]; then
        REMOVE_DATA=1
        REMOVE_APPS=1
    fi
done

# Пути для удаления
MS_BIN="/usr/local/bin/ms"
LIB_DIR="/usr/local/lib/minStack"
CREDENTIALS_DIR="/var/lib/minStack"
LOG_FILE="/var/log/minStack.log"

# Проверка, установлен ли MiniStack CLI
if [ ! -f "$MS_BIN" ] && [ ! -d "$LIB_DIR" ]; then
    echo -e "${YELLOW}MiniStack CLI не установлен или уже удален${NC}"
    exit 0
fi

echo -e "${YELLOW}ВНИМАНИЕ: Будет удален MiniStack CLI${NC}"
if [ "$REMOVE_APPS" -eq 1 ]; then
    echo -e "${RED}ВНИМАНИЕ: Будут удалены ВСЕ установленные приложения:${NC}"
    echo -e "${RED}  - Nginx${NC}"
    echo -e "${RED}  - MariaDB (все базы данных будут удалены!)${NC}"
    echo -e "${RED}  - PHP 7.4, 8.0, 8.1, 8.2, 8.3 и все расширения${NC}"
    echo -e "${RED}  - Certbot${NC}"
    echo -e "${RED}  - WP-CLI${NC}"
    echo -e "${RED}  - libidn2-0, idn2${NC}"
    echo -e "${RED}  - Репозитории PHP (Sury)${NC}"
    echo -e "${RED}  - Все сайты в /var/www/${NC}"
    echo -e "${RED}  - Конфигурации Nginx${NC}"
else
    echo -e "${YELLOW}Приложения будут сохранены (используйте --keep-apps для явного указания)${NC}"
fi
if [ "$REMOVE_DATA" -eq 1 ]; then
    echo -e "${RED}ВНИМАНИЕ: Будут удалены ВСЕ данные:${NC}"
    echo -e "${RED}  - Учетные данные (пароли MariaDB, пароли сайтов)${NC}"
    echo -e "${RED}  - Лог файлы${NC}"
    echo -e "${RED}  - Все скрипты и конфигурации${NC}"
else
    echo -e "${YELLOW}Данные (пароли, логи) будут сохранены в:${NC}"
    echo -e "${YELLOW}  - $CREDENTIALS_DIR${NC}"
    echo -e "${YELLOW}  - $LOG_FILE${NC}"
fi

# Запрос подтверждения
NEEDS_CONFIRMATION=1
for arg in "$@"; do
    if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
        NEEDS_CONFIRMATION=0
        break
    fi
done

if [ "$NEEDS_CONFIRMATION" -eq 1 ]; then
    if [ "$REMOVE_APPS" -eq 1 ]; then
        echo -e "${RED}ВНИМАНИЕ: Это удалит ВСЕ установленные приложения!${NC}"
    fi
    if [ "$REMOVE_DATA" -eq 1 ]; then
        echo -e "${RED}ВНИМАНИЕ: Это удалит ВСЕ данные!${NC}"
    fi
    echo -e "${BLUE}Продолжить? (yes/no):${NC}"
    read -r confirmation
    if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
        echo -e "${YELLOW}Удаление отменено${NC}"
        exit 0
    fi
fi

# Удаление главного исполняемого файла
echo -e "${BLUE}Удаляем главный исполняемый файл...${NC}"
if [ -f "$MS_BIN" ]; then
    rm -f "$MS_BIN"
    echo -e "${GREEN}Файл $MS_BIN удален${NC}"
else
    echo -e "${YELLOW}Файл $MS_BIN не найден${NC}"
fi

# Удаление библиотек скриптов
echo -e "${BLUE}Удаляем библиотеки скриптов...${NC}"
if [ -d "$LIB_DIR" ]; then
    rm -rf "$LIB_DIR"
    echo -e "${GREEN}Директория $LIB_DIR удалена${NC}"
else
    echo -e "${YELLOW}Директория $LIB_DIR не найдена${NC}"
fi

# Удаление данных (если указан --force)
if [ "$REMOVE_DATA" -eq 1 ]; then
    echo -e "${BLUE}Удаляем учетные данные...${NC}"
    if [ -d "$CREDENTIALS_DIR" ]; then
        rm -rf "$CREDENTIALS_DIR"
        echo -e "${GREEN}Директория $CREDENTIALS_DIR удалена${NC}"
    else
        echo -e "${YELLOW}Директория $CREDENTIALS_DIR не найдена${NC}"
    fi
    
    echo -e "${BLUE}Удаляем лог файлы...${NC}"
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        echo -e "${GREEN}Файл $LOG_FILE удален${NC}"
    else
        echo -e "${YELLOW}Файл $LOG_FILE не найден${NC}"
    fi
    
    # Удаляем родительскую директорию, если она пуста
    if [ -d "/var/lib/minStack" ] && [ -z "$(ls -A /var/lib/minStack 2>/dev/null)" ]; then
        rmdir /var/lib/minStack 2>/dev/null || true
    fi
else
    echo -e "${BLUE}Данные сохранены:${NC}"
    if [ -d "$CREDENTIALS_DIR" ]; then
        echo -e "${GREEN}  - Учетные данные: $CREDENTIALS_DIR${NC}"
    fi
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}  - Лог файл: $LOG_FILE${NC}"
    fi
fi

# Удаление установленных приложений
if [ "$REMOVE_APPS" -eq 1 ]; then
    echo -e "${BLUE}Удаляем установленные приложения...${NC}"
    
    # Останавливаем сервисы
    echo -e "${BLUE}Останавливаем сервисы...${NC}"
    systemctl stop nginx 2>/dev/null || true
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    
    # Удаляем PHP версии
    PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
    for version in "${PHP_VERSIONS[@]}"; do
        echo -e "${BLUE}Удаляем PHP $version...${NC}"
        systemctl stop php${version}-fpm 2>/dev/null || true
        systemctl disable php${version}-fpm 2>/dev/null || true
        apt remove -y --purge php${version}* 2>/dev/null || true
    done
    
    # Удаляем MariaDB
    echo -e "${BLUE}Удаляем MariaDB...${NC}"
    # Удаляем все базы данных (если есть доступ к паролю)
    if [ -f "$CREDENTIALS_DIR/mariadb_credentials.txt" ]; then
        DB_ROOT_PASS=$(grep "^MariaDB Root Password:" "$CREDENTIALS_DIR/mariadb_credentials.txt" | sed 's/^MariaDB Root Password: //' | sed 's/[[:space:]]*$//' | tr -d '\n\r' 2>/dev/null || echo "")
        if [ -n "$DB_ROOT_PASS" ]; then
            export MYSQL_PWD="$DB_ROOT_PASS"
            echo -e "${BLUE}Удаляем все базы данных...${NC}"
            # Получаем список всех баз данных (кроме системных)
            DATABASES=$(mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$" || true)
            for db in $DATABASES; do
                if [ -n "$db" ]; then
                    mysql -u root -e "DROP DATABASE IF EXISTS \`$db\`;" 2>/dev/null || true
                    echo -e "${GREEN}База данных $db удалена${NC}"
                fi
            done
            unset MYSQL_PWD
        fi
    fi
    # Останавливаем и удаляем MariaDB
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    systemctl disable mariadb 2>/dev/null || true
    systemctl disable mysql 2>/dev/null || true
    apt remove -y --purge mariadb-server mariadb-client 2>/dev/null || true
    apt remove -y --purge mysql-server mysql-client 2>/dev/null || true
    # Удаляем данные MariaDB
    if [ -d "/var/lib/mysql" ]; then
        rm -rf /var/lib/mysql
        echo -e "${GREEN}Данные MariaDB удалены${NC}"
    fi
    apt autoremove -y 2>/dev/null || true
    
    # Удаляем Nginx
    echo -e "${BLUE}Удаляем Nginx...${NC}"
    apt remove -y --purge nginx nginx-common 2>/dev/null || true
    
    # Удаляем Certbot
    echo -e "${BLUE}Удаляем Certbot...${NC}"
    apt remove -y --purge certbot python3-certbot-nginx 2>/dev/null || true
    
    # Удаляем WP-CLI
    echo -e "${BLUE}Удаляем WP-CLI...${NC}"
    if [ -f "/usr/local/bin/wp" ]; then
        rm -f /usr/local/bin/wp
        echo -e "${GREEN}WP-CLI удален${NC}"
    fi
    
    # Удаляем libidn2-0 и idn2
    echo -e "${BLUE}Удаляем libidn2-0 и idn2...${NC}"
    apt remove -y --purge libidn2-0 idn2 2>/dev/null || true
    
    # Удаляем репозитории PHP (Sury)
    echo -e "${BLUE}Удаляем репозитории PHP...${NC}"
    if [ -f "/etc/apt/sources.list.d/php.list" ]; then
        rm -f /etc/apt/sources.list.d/php.list
        echo -e "${GREEN}Репозиторий PHP удален${NC}"
    fi
    if [ -f "/etc/apt/trusted.gpg.d/php.gpg" ]; then
        rm -f /etc/apt/trusted.gpg.d/php.gpg
    fi
    
    # Удаляем конфигурации Nginx
    echo -e "${BLUE}Удаляем конфигурации Nginx...${NC}"
    if [ -d "/etc/nginx" ]; then
        rm -rf /etc/nginx
        echo -e "${GREEN}Конфигурации Nginx удалены${NC}"
    fi
    
    # Удаляем сайты
    echo -e "${BLUE}Удаляем сайты из /var/www/...${NC}"
    if [ -d "/var/www" ]; then
        # Сохраняем только если не используется другими приложениями
        # Удаляем только содержимое, созданное MiniStack
        find /var/www -mindepth 1 -maxdepth 1 -type d ! -name "html" -exec rm -rf {} \; 2>/dev/null || true
        if [ -d "/var/www/html" ]; then
            rm -rf /var/www/html/*
        fi
        echo -e "${GREEN}Сайты удалены${NC}"
    fi
    
    # Очистка зависимостей
    echo -e "${BLUE}Очищаем неиспользуемые пакеты...${NC}"
    apt autoremove -y 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    
    echo -e "${GREEN}Все приложения удалены${NC}"
fi

# Финальная проверка
if [ ! -f "$MS_BIN" ] && [ ! -d "$LIB_DIR" ]; then
    echo -e "${GREEN}=== MiniStack CLI успешно удален! ===${NC}"
    if [ "$REMOVE_DATA" -eq 0 ]; then
        echo -e "${YELLOW}Примечание: Данные сохранены.${NC}"
        echo -e "${YELLOW}Для удаления данных используйте:${NC}"
        echo -e "${YELLOW}  sudo ms --uninstall --force --yes${NC}"
    fi
    if [ "$REMOVE_APPS" -eq 0 ]; then
        echo -e "${YELLOW}Примечание: Приложения сохранены.${NC}"
    fi
else
    echo -e "${RED}Ошибка: некоторые файлы не были удалены${NC}"
    exit 1
fi

