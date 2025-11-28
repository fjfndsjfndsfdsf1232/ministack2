#!/bin/bash
# ms - Точка входа для MiniStack CLI
# Версия 1.0.31

# Проверка, что используется bash
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: Скрипт должен выполняться в Bash, а не в sh"
    exit 1
fi

# Обработка команд --update и --uninstall до загрузки других файлов (на случай, если они повреждены)
if [ "$1" = "--update" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Обновление требует прав root. Запустите: sudo ms --update"
        exit 1
    fi
    # Запускаем скрипт обновления
    if [ -f "/usr/local/lib/minStack/update_minstack.sh" ]; then
        bash /usr/local/lib/minStack/update_minstack.sh
    else
        # Если скрипт обновления еще не установлен, скачиваем его временно
        REPO_DIR="/tmp/MiniStack-CLI-update-$$"
        if command -v git >/dev/null 2>&1; then
            git clone https://gitlab504.xyz/root/ministack.git "$REPO_DIR" >/dev/null 2>&1
            if [ -f "$REPO_DIR/update_minstack.sh" ]; then
                bash "$REPO_DIR/update_minstack.sh"
                rm -rf "$REPO_DIR"
            else
                echo "ERROR: Не удалось найти скрипт обновления"
                rm -rf "$REPO_DIR"
                exit 1
            fi
        else
            echo "ERROR: Git не установлен. Установите: apt install -y git"
            exit 1
        fi
    fi
    exit 0
fi

if [ "$1" = "--uninstall" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Удаление требует прав root. Запустите: sudo ms --uninstall"
        exit 1
    fi
    # Запускаем скрипт удаления
    if [ -f "/usr/local/lib/minStack/uninstall_minstack.sh" ]; then
        bash /usr/local/lib/minStack/uninstall_minstack.sh "$2"
    else
        # Если скрипт удаления не найден, скачиваем его временно
        REPO_DIR="/tmp/MiniStack-CLI-uninstall-$$"
        if command -v git >/dev/null 2>&1; then
            git clone https://gitlab504.xyz/root/ministack.git "$REPO_DIR" >/dev/null 2>&1
            if [ -f "$REPO_DIR/uninstall_minstack.sh" ]; then
                bash "$REPO_DIR/uninstall_minstack.sh" "$2"
                rm -rf "$REPO_DIR"
            else
                echo "ERROR: Не удалось найти скрипт удаления"
                rm -rf "$REPO_DIR"
                exit 1
            fi
        else
            echo "ERROR: Git не установлен. Установите: apt install -y git"
            exit 1
        fi
    fi
    exit 0
fi

# Проверка наличия файлов перед их подключением
LIB_DIR="/usr/local/lib/minStack"
FILES=("config.sh" "core.sh" "nginx_utils.sh" "utils.sh" "stack_install.sh" "site_create.sh" "site_bulk_create.sh" "site_bulk_delete.sh" "site_delete.sh" "site_info.sh" "secure_ssl.sh" "clean_headers.sh" "show_info.sh")

for file in "${FILES[@]}"; do
    if [ ! -f "$LIB_DIR/$file" ]; then
        echo "ERROR: Файл $LIB_DIR/$file не найден"
        exit 1
    fi
done

. "$LIB_DIR/config.sh"
. "$LIB_DIR/core.sh"
. "$LIB_DIR/nginx_utils.sh"
. "$LIB_DIR/utils.sh"
. "$LIB_DIR/stack_install.sh"
. "$LIB_DIR/site_create.sh"
. "$LIB_DIR/site_bulk_create.sh"
. "$LIB_DIR/site_bulk_delete.sh"
. "$LIB_DIR/site_delete.sh"
. "$LIB_DIR/site_info.sh"
. "$LIB_DIR/secure_ssl.sh"
. "$LIB_DIR/clean_headers.sh"
. "$LIB_DIR/show_info.sh"

# Парсинг команд
case "$1" in
    stack)
        case "$2" in
            --install) install_stack ;;
            *) log_message "error" "Укажите --install для команды stack"; exit 1 ;;
        esac
        ;;
    site)
        case "$2" in
            --create)
                if [ -z "$3" ]; then
                    log_message "error" "Укажите домен после --create"
                    exit 1
                else
                    shift 2
                    create_site "$@"
                fi
                ;;
            --bulk) bulk_create_sites ;;
            --bulk-delete) bulk_delete_sites ;;
            --delete)
                if [ -z "$3" ]; then
                    log_message "error" "Укажите домен после --delete"
                    exit 1
                fi
                delete_site "$3"
                ;;
            --info)
                if [ -z "$3" ]; then
                    log_message "error" "Укажите домен после --info"
                    exit 1
                fi
                site_info "$3"
                ;;
            *) log_message "error" "Укажите --create, --bulk, --bulk-delete, --delete или --info"; exit 1 ;;
        esac
        ;;
    secure)
        if [ "$2" = "--ssl" ]; then
            if [ -z "$3" ]; then
                log_message "error" "Укажите домен после --ssl"
                exit 1
            fi
            if [[ "$4" == "--letsencrypt" || "$4" == "--selfsigned" || -z "$4" ]]; then
                setup_ssl "$3" "$4"
            else
                log_message "error" "Неверный флаг для secure --ssl: $4. Используйте --letsencrypt или --selfsigned"
                exit 1
            fi
        else
            log_message "error" "Укажите --ssl и домен"
            exit 1
        fi
        ;;
    --clean) clean_headers ;;
    --info) show_info ;;
    --update)
        log_message "info" "Команда --update должна быть вызвана напрямую: sudo ms --update"
        log_message "info" "Она обрабатывается до загрузки других файлов для безопасности"
        exit 1
        ;;
    --uninstall)
        log_message "info" "Команда --uninstall должна быть вызвана напрямую: sudo ms --uninstall"
        log_message "info" "Она обрабатывается до загрузки других файлов для безопасности"
        exit 1
        ;;
    --help) show_help ;;
    *) log_message "error" "Неизвестная команда: $1"; exit 1 ;;
esac
