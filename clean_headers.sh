# clean_headers.sh - Команда для очистки HTTP-заголовков в MiniStack CLI
# Версия 1.0.31

clean_headers() {
    clean_old_logs
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --clean: $@. Используйте без флагов"
        exit 1
    fi
    log_message "info" "Настраиваем чистые HTTP-заголовки..." "start_operation"
    if ! grep -q "server_tokens off" /etc/nginx/nginx.conf; then
        sed -i '/http {/a\    server_tokens off;' /etc/nginx/nginx.conf
    fi
    for version in "${PHP_VERSIONS[@]}"; do
        systemctl restart php${version}-fpm
        check_service php${version}-fpm
    done
    nginx -t && systemctl restart nginx
    check_service nginx
    log_message "success" "HTTP-заголовки настроены!"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Настройка заголовков завершена" "end_operation" "Настройка заголовков завершена"
}
