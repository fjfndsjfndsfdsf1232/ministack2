#!/bin/bash
# convert_credentials.sh - Конвертация site_credentials.txt в простой формат
# Версия 1.0.31

INPUT_FILE="${1:-site_credentials.txt}"
OUTPUT_FILE="${2:-site_credentials_simple.txt}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: файл $INPUT_FILE не найден"
    exit 1
fi

echo "Конвертируем $INPUT_FILE в формат: https://site.ru;admin;pass"
echo ""

# Временные переменные
CURRENT_SITE=""
CURRENT_USER=""
CURRENT_PASS=""
OUTPUT_LINES=()

# Читаем файл построчно
while IFS= read -r line || [ -n "$line" ]; do
    # Убираем пробелы в начале и конце
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Пропускаем пустые строки и разделители
    if [ -z "$line" ] || [ "$line" = "-------------------" ]; then
        # Если нашли разделитель и у нас есть данные, сохраняем запись
        if [ -n "$CURRENT_SITE" ] && [ -n "$CURRENT_USER" ] && [ -n "$CURRENT_PASS" ]; then
            OUTPUT_LINES+=("https://$CURRENT_SITE;$CURRENT_USER;$CURRENT_PASS")
            CURRENT_SITE=""
            CURRENT_USER=""
            CURRENT_PASS=""
        fi
        continue
    fi
    
    # Извлекаем Site
    if [[ "$line" =~ ^Site:[[:space:]]*(.+)$ ]]; then
        CURRENT_SITE="${BASH_REMATCH[1]}"
    fi
    
    # Извлекаем WordPress Admin User
    if [[ "$line" =~ ^WordPress[[:space:]]+Admin[[:space:]]+User:[[:space:]]*(.+)$ ]]; then
        CURRENT_USER="${BASH_REMATCH[1]}"
    fi
    
    # Извлекаем WordPress Admin Password
    if [[ "$line" =~ ^WordPress[[:space:]]+Admin[[:space:]]+Password:[[:space:]]*(.+)$ ]]; then
        CURRENT_PASS="${BASH_REMATCH[1]}"
    fi
    
done < "$INPUT_FILE"

# Сохраняем последнюю запись, если она есть
if [ -n "$CURRENT_SITE" ] && [ -n "$CURRENT_USER" ] && [ -n "$CURRENT_PASS" ]; then
    OUTPUT_LINES+=("https://$CURRENT_SITE;$CURRENT_USER;$CURRENT_PASS")
fi

# Записываем результат в файл
> "$OUTPUT_FILE"
for line in "${OUTPUT_LINES[@]}"; do
    echo "$line" >> "$OUTPUT_FILE"
    echo "$line"
done

echo ""
echo "✓ Конвертация завершена!"
echo "Результат сохранен в: $OUTPUT_FILE"
echo "Всего записей: ${#OUTPUT_LINES[@]}"












