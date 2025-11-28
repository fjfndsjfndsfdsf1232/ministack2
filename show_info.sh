# show_info.sh - Команда для отображения статуса сервисов в MiniStack CLI
# Версия 1.0.31

show_info() {
    clean_old_logs
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --info: $@. Используйте без флагов"
        exit 1
    fi
    log_message "info" "Проверяем статус сервисов..." "start_operation"
    systemctl status nginx --no-pager
    for version in "${PHP_VERSIONS[@]}"; do
        systemctl status php${version}-fpm --no-pager
    done
    systemctl status mariadb --no-pager
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Статус сервисов отображён" "end_operation" "Статус сервисов отображён"
}
