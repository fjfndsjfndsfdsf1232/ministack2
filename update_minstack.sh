#!/bin/bash

# update_minstack.sh - Обновление MiniStack CLI из GitLab репозитория
# Версия 1.0.31

set -e

# Цвета для вывода
BLUE='\033[0;38;2;0;255;255m'
GREEN='\033[0;38;2;0;255;0m'
RED='\033[0;38;2;255;0;0m'
YELLOW='\033[0;38;2;255;255;0m'
NC='\033[0m'

echo -e "${BLUE}=== MiniStack CLI Update ===${NC}"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен с правами root (используйте sudo)${NC}"
    exit 1
fi

# Проверка свободного места на диске (>100MB)
if [ $(df -m / | tail -1 | awk '{print $4}') -lt 100 ]; then
    echo -e "${RED}Недостаточно места на диске (<100MB)${NC}"
    exit 1
fi

# Проверка наличия git
if ! command -v git >/dev/null 2>&1; then
    echo -e "${YELLOW}Git не установлен. Устанавливаем...${NC}"
    apt update
    apt install -y git
fi

# Проверка наличия dos2unix
if ! command -v dos2unix >/dev/null 2>&1; then
    echo -e "${BLUE}Устанавливаем dos2unix...${NC}"
    apt update
    apt install -y dos2unix
fi

# Директория для клонирования
REPO_DIR="/tmp/MiniStack-CLI-update-$$"

# Удаляем старую папку, если существует
if [ -d "$REPO_DIR" ]; then
    echo -e "${BLUE}Удаляем старую временную папку...${NC}"
    rm -rf "$REPO_DIR"
fi

# Клонирование репозитория
echo -e "${BLUE}Клонируем репозиторий...${NC}"
if ! git clone https://github.com/fjfndsjfndsfdsf1232/ministack2.git "$REPO_DIR" 2>&1; then
    echo -e "${RED}Ошибка: не удалось клонировать репозиторий${NC}"
    exit 1
fi

# Проверка наличия файлов
FILES=("ms" "config.sh" "core.sh" "nginx_utils.sh" "stack_install.sh" "site_create.sh" "site_bulk_create.sh" "site_bulk_create_multisite.sh" "site_bulk_delete.sh" "site_delete.sh" "site_info.sh" "site_app_key.sh" "secure_ssl.sh" "clean_headers.sh" "show_info.sh" "utils.sh")
echo -e "${BLUE}Проверяем наличие файлов...${NC}"
for file in "${FILES[@]}"; do
    if [ ! -f "$REPO_DIR/$file" ]; then
        echo -e "${RED}Ошибка: файл $file не найден в репозитории${NC}"
        rm -rf "$REPO_DIR"
        exit 1
    fi
done

# Конвертация CRLF в LF
echo -e "${BLUE}Конвертируем файлы в формат LF...${NC}"
for file in "${FILES[@]}"; do
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$REPO_DIR/$file" >/dev/null 2>&1
    else
        sed -i 's/\r$//' "$REPO_DIR/$file"
    fi
done

# Создание директорий
echo -e "${BLUE}Создаём директории...${NC}"
mkdir -p /usr/local/lib/minStack

# Резервное копирование текущих файлов
BACKUP_DIR="/tmp/minStack-backup-$$"
if [ -d "/usr/local/lib/minStack" ]; then
    echo -e "${BLUE}Создаём резервную копию текущих файлов...${NC}"
    mkdir -p "$BACKUP_DIR"
    cp -r /usr/local/lib/minStack/* "$BACKUP_DIR/" 2>/dev/null || true
    cp /usr/local/bin/ms "$BACKUP_DIR/ms" 2>/dev/null || true
fi

# Копирование файлов
echo -e "${BLUE}Копируем обновленные файлы...${NC}"
cp "$REPO_DIR/ms" /usr/local/bin/ms
cp "$REPO_DIR/config.sh" /usr/local/lib/minStack/config.sh
cp "$REPO_DIR/core.sh" /usr/local/lib/minStack/core.sh
cp "$REPO_DIR/nginx_utils.sh" /usr/local/lib/minStack/nginx_utils.sh
cp "$REPO_DIR/stack_install.sh" /usr/local/lib/minStack/stack_install.sh
cp "$REPO_DIR/site_create.sh" /usr/local/lib/minStack/site_create.sh
cp "$REPO_DIR/site_bulk_create.sh" /usr/local/lib/minStack/site_bulk_create.sh
cp "$REPO_DIR/site_bulk_create_multisite.sh" /usr/local/lib/minStack/site_bulk_create_multisite.sh
cp "$REPO_DIR/site_bulk_delete.sh" /usr/local/lib/minStack/site_bulk_delete.sh
cp "$REPO_DIR/site_delete.sh" /usr/local/lib/minStack/site_delete.sh
cp "$REPO_DIR/site_info.sh" /usr/local/lib/minStack/site_info.sh
cp "$REPO_DIR/site_app_key.sh" /usr/local/lib/minStack/site_app_key.sh
cp "$REPO_DIR/secure_ssl.sh" /usr/local/lib/minStack/secure_ssl.sh
cp "$REPO_DIR/clean_headers.sh" /usr/local/lib/minStack/clean_headers.sh
cp "$REPO_DIR/show_info.sh" /usr/local/lib/minStack/show_info.sh
cp "$REPO_DIR/utils.sh" /usr/local/lib/minStack/utils.sh

# Проверка, что ms скопировался
if [ ! -f "/usr/local/bin/ms" ]; then
    echo -e "${RED}Ошибка: файл /usr/local/bin/ms не скопировался. Восстанавливаем из резервной копии...${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        cp -r "$BACKUP_DIR"/* /usr/local/lib/minStack/ 2>/dev/null || true
        cp "$BACKUP_DIR/ms" /usr/local/bin/ms 2>/dev/null || true
    fi
    rm -rf "$REPO_DIR" "$BACKUP_DIR"
    exit 1
fi

# Установка прав
echo -e "${BLUE}Настраиваем права доступа...${NC}"
chmod +x /usr/local/bin/ms
chmod 644 /usr/local/lib/minStack/*.sh

# Проверка прав на ms
if [ ! -x "/usr/local/bin/ms" ]; then
    echo -e "${RED}Ошибка: файл /usr/local/bin/ms не имеет прав на выполнение. Восстанавливаем из резервной копии...${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        cp -r "$BACKUP_DIR"/* /usr/local/lib/minStack/ 2>/dev/null || true
        cp "$BACKUP_DIR/ms" /usr/local/bin/ms 2>/dev/null || true
        chmod +x /usr/local/bin/ms
    fi
    rm -rf "$REPO_DIR" "$BACKUP_DIR"
    exit 1
fi

# Проверка синтаксиса главного файла
echo -e "${BLUE}Проверяем синтаксис...${NC}"
if ! bash -n /usr/local/bin/ms; then
    echo -e "${RED}Ошибка: синтаксическая ошибка в /usr/local/bin/ms. Восстанавливаем из резервной копии...${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        cp -r "$BACKUP_DIR"/* /usr/local/lib/minStack/ 2>/dev/null || true
        cp "$BACKUP_DIR/ms" /usr/local/bin/ms 2>/dev/null || true
        chmod +x /usr/local/bin/ms
    fi
    rm -rf "$REPO_DIR" "$BACKUP_DIR"
    exit 1
fi

# Удаление временных папок
echo -e "${BLUE}Очищаем временные файлы...${NC}"
rm -rf "$REPO_DIR"
rm -rf "$BACKUP_DIR"

echo -e "${GREEN}=== Обновление MiniStack CLI завершено успешно! ===${NC}"
echo -e "${BLUE}Используйте 'sudo ms --help' для просмотра доступных команд${NC}"

