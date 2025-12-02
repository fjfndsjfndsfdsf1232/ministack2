#!/bin/bash
# show_credentials_example.sh - Пример файла с credentials MariaDB
# Версия 1.0.31

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Пример файла с credentials MariaDB ===${NC}"
echo ""

echo -e "${YELLOW}Путь к файлу:${NC}"
echo "/var/lib/minStack/credentials/mariadb_credentials.txt"
echo ""

echo -e "${YELLOW}Структура файла:${NC}"
echo "┌─────────────────────────────────────────────────┐"
echo "│ MariaDB Root Password: <сгенерированный_пароль> │"
echo "└─────────────────────────────────────────────────┘"
echo ""

echo -e "${YELLOW}Пример содержимого:${NC}"
echo "MariaDB Root Password: HKG5wkWhJgWQGc/s"
echo ""

echo -e "${YELLOW}Права доступа:${NC}"
echo "-rw------- 1 root root (600) - только root может читать/писать"
echo ""

echo -e "${YELLOW}Директория:${NC}"
echo "/var/lib/minStack/credentials/"
echo "  ├── mariadb_credentials.txt  (пароль root MariaDB)"
echo "  └── site_credentials.txt     (данные сайтов)"
echo ""

echo -e "${YELLOW}Как извлекается пароль в скриптах:${NC}"
cat <<'CODE'
DB_ROOT_PASS=$(grep "^MariaDB Root Password:" "$MARIADB_CREDENTIALS" | \
    sed 's/^MariaDB Root Password: //' | \
    sed 's/[[:space:]]*$//' | \
    tr -d '\n\r')
CODE

echo ""
echo -e "${GREEN}Для просмотра реального файла в Docker:${NC}"
echo "bash test_show_credentials.sh"






