#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
DEFAULT='\033[0m'


CRON_FILE="/etc/crontab"
BACKUP_DIR="/etc/cron.backups"


# Функции пользовательского интерфейса

# Главное меню
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════╗${DEFAULT}"
    echo -e "${BLUE}║${GREEN}           Cron Manager             ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}╠════════════════════════════════════╣${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 1) Просмотр задач                  ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 2) Добавить задачу                 ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 3) Редактировать задачу            ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 4) Удалить задачу                  ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 5) Проверить синтаксис задачи      ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 6) Статус cron сервиса             ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}║${DEFAULT} 0) Выход                           ${BLUE}║${DEFAULT}"
    echo -e "${BLUE}╚════════════════════════════════════╝${DEFAULT}"
}

# Пауза до нажатия Enter
pause() {
    echo -e "${YELLOW}Нажмите Enter для продолжения...${DEFAULT}"
    read -r
}

# Инструкциб по созданию cron
show_task_format_info() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${DEFAULT}"
    echo -e "${GREEN}ФОРМАТ ЗАДАЧИ CRON:${DEFAULT}"
    echo -e "${YELLOW}минуты часы дни месяцы дни_недели${DEFAULT}"
    echo
    echo -e "${GREEN}СПЕЦИАЛЬНЫЕ ЗНАЧЕНИЯ:${DEFAULT}"
    echo -e "  ${PURPLE}@reboot${DEFAULT}    - при каждом запуске системы"
    echo -e "  ${PURPLE}@yearly${DEFAULT}    - 0 0 1 1 * (раз в год)"
    echo -e "  ${PURPLE}@annually${DEFAULT}  - 0 0 1 1 * (раз в год)"
    echo -e "  ${PURPLE}@monthly${DEFAULT}   - 0 0 1 * * (раз в месяц)"
    echo -e "  ${PURPLE}@weekly${DEFAULT}    - 0 0 * * 0 (раз в неделю)"
    echo -e "  ${PURPLE}@daily${DEFAULT}     - 0 0 * * * (каждый день)"
    echo -e "  ${PURPLE}@hourly${DEFAULT}    - 0 * * * * (каждый час)"
    echo
    echo -e "${GREEN}СИМВОЛЫ:${DEFAULT}"
    echo -e "  ${YELLOW}*${DEFAULT} - любое значение"
    echo -e "  ${YELLOW},${DEFAULT} - список значений (1,2,3)"
    echo -e "  ${YELLOW}-${DEFAULT} - диапазон значений (1-5)"
    echo -e "  ${YELLOW}/${DEFAULT} - шаг значений (*/5 = каждые 5)"
    echo
    echo -e "${GREEN}ПРИМЕРЫ:${DEFAULT}"
    echo -e "  ${CYAN}*/5 * * * * root /script.sh${DEFAULT}     - каждые 5 минут"
    echo -e "  ${CYAN}0 2 * * * root /backup.sh${DEFAULT}       - каждый день в 2:00"
    echo -e "  ${CYAN}0 0 * * 0 root /weekly.sh${DEFAULT}       - каждое воскресенье"
    echo -e "  ${CYAN}@daily root /daily.sh${DEFAULT}           - каждый день"
    echo -e "  ${CYAN}@reboot root /startup.sh${DEFAULT}        - при загрузке"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${DEFAULT}"
}

# Подтверждение
confirm_action() {
    local action=$1
    local item=$2
    read -r -e -p $'\[\033[1;33m\]Вы хотите '"$action $item? (y/n): \[\033[0m\]" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Действие отменено${DEFAULT}"
        return 1
    fi
    return 0
}


# Функции работы с резервными копиями и безопасной записи

# Создаёт резервную копию /etc/crontab в папке BACKUP_DIR с меткой времени
create_backup() {
    sudo mkdir -p "$BACKUP_DIR" 2>/dev/null
    local backup_file="$BACKUP_DIR/crontab.backup.$(date +%Y%m%d_%H%M%S)"
    if sudo cp "$CRON_FILE" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}Создан backup: $backup_file${DEFAULT}"
        BACKUP_FILE="$backup_file"
        return 0
    else
        echo -e "${RED}Ошибка: Не удалось создать backup${DEFAULT}"
        return 1
    fi
}

# Восстанавливает файл crontab из последнего созданного бэкапа (если есть)
restore_backup() {
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        echo -e "${YELLOW}Попытка восстановления из бэкапа $BACKUP_FILE${DEFAULT}"
        if sudo cp "$BACKUP_FILE" "$CRON_FILE"; then
            echo -e "${GREEN}Восстановление выполнено${DEFAULT}"
            return 0
        else
            echo -e "${RED}Критическая ошибка: не удалось восстановить бэкап!${DEFAULT}"
            return 1
        fi
    fi
    return 1
}

# Перезагружает сервис cron
reload_cron() {
    echo -e "${YELLOW}Перезагрузка cron сервиса...${DEFAULT}"
    if systemctl list-units --full -all | grep -Fq 'cron.service'; then
        sudo systemctl try-reload-or-restart cron
    elif systemctl list-units --full -all | grep -Fq 'crond.service'; then
        sudo systemctl try-reload-or-restart crond
    else
        echo -e "${RED}Не удалось найти сервис cron. Изменения вступят после перезагрузки.${DEFAULT}"
    fi
}

# Безопасно записывает изменения в /etc/crontab:
# - создаёт бэкап
# - перемещает временный файл на место оригинального
# - в случае ошибки восстанавливает из бэкапа
# Параметры: $1 - оригинальный файл, $2 - временный файл с новым содержимым
safe_write() {
    local orig_file=$1
    local temp_file=$2
    local backup_success=false

    if create_backup; then
        backup_success=true
    else
        echo -e "${RED}Не удалось создать бэкап, операция прервана${DEFAULT}"
        return 1
    fi

    if sudo mv "$temp_file" "$orig_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Изменения сохранены${DEFAULT}"
        reload_cron
        return 0
    else
        echo -e "${RED}Ошибка при записи в $orig_file${DEFAULT}"
        if $backup_success; then
            restore_backup
        fi
        return 1
    fi
}


# Функции валидации cron-задач

# Проверяет существования пользователя
user_exists() {
    id "$1" &>/dev/null
}

# Проверяет одно временное поле на корректность формата и диапазона
# Поддерживает *, списки через запятую, диапазоны, шаги и их комбинации
check_time_field() {
    local field=$1
    local name=$2
    local min=$3
    local max=$4

    [ "$field" = "*" ] && return 0

    IFS=',' read -ra parts <<< "$field"
    for part in "${parts[@]}"; do
        # диапазон с шагом: начало-конец/шаг
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)/([0-9]+)$ ]]; then
            local start=${BASH_REMATCH[1]}
            local end=${BASH_REMATCH[2]}
            local step=${BASH_REMATCH[3]}
            if [ "$start" -lt "$min" ] || [ "$end" -gt "$max" ] || [ "$step" -le 0 ]; then
                echo -e "${RED}Ошибка: Неверный диапазон с шагом '$part' в поле '$name'${DEFAULT}"
                return 1
            fi
        # простой диапазон: начало-конец
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start=${BASH_REMATCH[1]}
            local end=${BASH_REMATCH[2]}
            if [ "$start" -lt "$min" ] || [ "$end" -gt "$max" ] || [ "$start" -gt "$end" ]; then
                echo -e "${RED}Ошибка: Неверный диапазон '$part' в поле '$name'${DEFAULT}"
                return 1
            fi
        # шаг от любого значения: */шаг
        elif [[ "$part" =~ ^\*/([0-9]+)$ ]]; then
            local step=${BASH_REMATCH[1]}
            if [ "$step" -le 0 ]; then
                echo -e "${RED}Ошибка: Неверный шаг '$part' в поле '$name'${DEFAULT}"
                return 1
            fi
        # значение/шаг (редкий случай, но допустимый)
        elif [[ "$part" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            local val=${BASH_REMATCH[1]}
            local step=${BASH_REMATCH[2]}
            if [ "$val" -lt "$min" ] || [ "$val" -gt "$max" ] || [ "$step" -le 0 ]; then
                echo -e "${RED}Ошибка: Неверное значение/шаг '$part' в поле '$name'${DEFAULT}"
                return 1
            fi
        # простое число
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if [ "$part" -lt "$min" ] || [ "$part" -gt "$max" ]; then
                echo -e "${RED}Ошибка: Значение $part в поле '$name' должно быть в диапазоне $min-$max${DEFAULT}"
                return 1
            fi
        else
            echo -e "${RED}Ошибка: Некорректный формат '$part' в поле '$name'${DEFAULT}"
            return 1
        fi
    done
    return 0
}

# Основная функция проверки синтаксиса целой строки cron
# Поддерживает как обычные задачи так и специальные (@reboot, @daily)
check_syntax() {
    local task=$1

    if [ -z "$task" ]; then
        echo -e "${RED}Ошибка: Задача не может быть пустой${DEFAULT}"
        return 1
    fi

    # Обработка специальных меток
    if [[ "$task" =~ ^@[a-zA-Z]+\ +([^ ]+)\ +(.+)$ ]]; then
        local special="${BASH_REMATCH[0]%% *}"
        local user="${BASH_REMATCH[1]}"
        local command="${BASH_REMATCH[2]}"
        case "$special" in
            @reboot|@yearly|@annually|@monthly|@weekly|@daily|@hourly)
                if [ -z "$user" ]; then
                    echo -e "${RED}Ошибка: В специальной задаче не указан пользователь${DEFAULT}"
                    return 1
                fi
                if ! user_exists "$user"; then
                    echo -e "${RED}Ошибка: Пользователь '$user' не существует${DEFAULT}"
                    return 1
                fi
                if [ -z "$command" ]; then
                    echo -e "${RED}Ошибка: Не указана команда${DEFAULT}"
                    return 1
                fi
                echo -e "${GREEN}✓ Корректный специальный синтаксис: $special${DEFAULT}"
                return 0
                ;;
            *)
                echo -e "${RED}Ошибка: Неизвестный специальный параметр '$special'${DEFAULT}"
                echo -e "${YELLOW}Допустимые: @reboot, @yearly, @annually, @monthly, @weekly, @daily, @hourly${DEFAULT}"
                return 1
                ;;
        esac
    fi

    # Обычная задача
    local fields=$(echo "$task" | awk '{print NF}')
    if [ "$fields" -lt 6 ]; then
        echo -e "${RED}Ошибка: Недостаточно полей в задаче (минимум 6: минуты часы дни месяцы дни_недели пользователь команда)${DEFAULT}"
        return 1
    fi

    # Извлекаем поля
    local minute=$(echo "$task" | awk '{print $1}')
    local hour=$(echo "$task" | awk '{print $2}')
    local day=$(echo "$task" | awk '{print $3}')
    local month=$(echo "$task" | awk '{print $4}')
    local weekday=$(echo "$task" | awk '{print $5}')
    local user=$(echo "$task" | awk '{print $6}')
    local command=$(echo "$task" | cut -d' ' -f7-)

    # Проверка пользователя
    if ! user_exists "$user"; then
        echo -e "${RED}Ошибка: Пользователь '$user' не существует${DEFAULT}"
        return 1
    fi

    # Проверка наличия команды
    if [ -z "$command" ]; then
        echo -e "${RED}Ошибка: Не указана команда${DEFAULT}"
        return 1
    fi

    # Проверка каждого временного поля
    check_time_field "$minute" "минуты" 0 59 || return 1
    check_time_field "$hour" "часы" 0 23 || return 1
    check_time_field "$day" "дни" 1 31 || return 1
    check_time_field "$month" "месяцы" 1 12 || return 1
    check_time_field "$weekday" "дни_недели" 0 7 || return 1

    echo -e "${GREEN}✓ Синтаксис корректный${DEFAULT}"
    return 0
}


# Функции для работы с задачами

# Добавление новой задачи
add_task() {
    echo -e "${GREEN}Добавление новой задачи${DEFAULT}"
    show_task_format_info
    echo

    read -r -e -p "Введите задачу (Enter - отмена): " new_task

    if [ -z "$new_task" ]; then
        echo -e "${YELLOW}Добавление отменено${DEFAULT}"
        pause
        return 0
    fi

    # Проверка синтаксиса перед добавлением
    if ! check_syntax "$new_task"; then
        pause
        return 1
    fi

    if confirm_action "добавить задачу" "\"$new_task\""; then
        local temp_file
        temp_file=$(mktemp) || { echo -e "${RED}Ошибка создания временного файла${DEFAULT}"; pause; return 1; }
        # Гарантируем удаление временного файла при выходе из функции
        trap 'rm -f "$temp_file"' EXIT

        # Копируем текущий crontab во временный файл и добавляем новую строку
        sudo cp "$CRON_FILE" "$temp_file" 2>/dev/null || true
        echo "$new_task" >> "$temp_file"

        if safe_write "$CRON_FILE" "$temp_file"; then
            : 
        else
            echo -e "${RED}Не удалось добавить задачу${DEFAULT}"
        fi
        rm -f "$temp_file"
        trap - EXIT
    fi

    pause
}

# Читает все незакомментарные и непустые строки из crontab в глобальный массив tasks
get_tasks_array() {
    tasks=()
    while IFS= read -r line; do
        tasks+=("$line")
    done < <(grep -v "^#" "$CRON_FILE" | grep -v "^$")
}

# Редактирование существующей задачи
edit_task() {
    if [ ! -f "$CRON_FILE" ]; then
        echo -e "${RED}Файл $CRON_FILE не найден${DEFAULT}"
        pause
        return 1
    fi

    echo -e "${GREEN}Редактирование задачи${DEFAULT}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${DEFAULT}"
    echo -e "${GREEN}ИНСТРУКЦИЯ ПО РЕДАКТИРОВАНИЮ:${DEFAULT}"
    echo -e "  • Выберите номер задачи из списка"
    echo -e "  • Введите новую задачу в формате cron"
    echo -e "  • Пустая строка - отмена"
    echo -e "  • Будет создан backup перед изменениями"
    echo
    show_task_format_info
    echo "-----------------------------------"

    # Получаем список задач
    tasks=()
    get_tasks_array

    if [ ${#tasks[@]} -eq 0 ]; then
        echo -e "${RED}Нет задач для редактирования${DEFAULT}"
        pause
        return 1
    fi

    # Выводим задачи с номерами
    for i in "${!tasks[@]}"; do
        echo "$((i+1))) ${tasks[$i]}"
    done
    echo "-----------------------------------"

    read -r -e -p "Введите номер задачи для редактирования (Enter - отмена): " task_num

    if [ -z "$task_num" ]; then
        echo -e "${YELLOW}Редактирование отменено${DEFAULT}"
        pause
        return 0
    fi

    # Проверка введённого номера
    if ! [[ "$task_num" =~ ^[0-9]+$ ]] || [ "$task_num" -lt 1 ] || [ "$task_num" -gt ${#tasks[@]} ]; then
        echo -e "${RED}Неверный номер задачи${DEFAULT}"
        pause
        return 1
    fi

    local idx=$((task_num-1))
    local old_task="${tasks[$idx]}"
    echo -e "${YELLOW}Текущая задача:${DEFAULT} $old_task"
    read -r -e -p "Введите новую задачу (Enter - отмена): " new_task

    if [ -z "$new_task" ]; then
        echo -e "${YELLOW}Редактирование отменено${DEFAULT}"
        pause
        return 0
    fi

    # Проверка синтаксиса новой задачи
    if ! check_syntax "$new_task"; then
        pause
        return 1
    fi

    if confirm_action "заменить задачу" "\"$old_task\" на \"$new_task\""; then
        local temp_file
        temp_file=$(mktemp) || { echo -e "${RED}Ошибка создания временного файла${DEFAULT}"; pause; return 1; }
        trap 'rm -f "$temp_file"' EXIT

        # Переписываем файл, заменяя нужную строку
        local count=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
                echo "$line" >> "$temp_file"
            else
                if [ $count -eq $idx ]; then
                    echo "$new_task" >> "$temp_file"
                else
                    echo "$line" >> "$temp_file"
                fi
                ((count++))
            fi
        done < "$CRON_FILE"

        if safe_write "$CRON_FILE" "$temp_file"; then
            : 
        else
            echo -e "${RED}Не удалось отредактировать задачу${DEFAULT}"
        fi
        rm -f "$temp_file"
        trap - EXIT
    fi

    pause
}

# Удаление задачи
delete_task() {
    if [ ! -f "$CRON_FILE" ]; then
        echo -e "${RED}Файл $CRON_FILE не найден${DEFAULT}"
        pause
        return 1
    fi

    echo -e "${GREEN}Удаление задачи${DEFAULT}"
    echo "-----------------------------------"

    tasks=()
    get_tasks_array

    if [ ${#tasks[@]} -eq 0 ]; then
        echo -e "${RED}Нет задач для удаления${DEFAULT}"
        pause
        return 1
    fi

    for i in "${!tasks[@]}"; do
        echo "$((i+1))) ${tasks[$i]}"
    done
    echo "-----------------------------------"

    read -r -e -p "Введите номер задачи для удаления (Enter - отмена): " task_num

    if [ -z "$task_num" ]; then
        echo -e "${YELLOW}Удаление отменено${DEFAULT}"
        pause
        return 0
    fi

    if ! [[ "$task_num" =~ ^[0-9]+$ ]] || [ "$task_num" -lt 1 ] || [ "$task_num" -gt ${#tasks[@]} ]; then
        echo -e "${RED}Неверный номер задачи${DEFAULT}"
        pause
        return 1
    fi

    local idx=$((task_num-1))
    local task_to_delete="${tasks[$idx]}"
    echo -e "${YELLOW}Задача для удаления:${DEFAULT} $task_to_delete"

    if confirm_action "удалить задачу" "\"$task_to_delete\""; then
        local temp_file
        temp_file=$(mktemp) || { echo -e "${RED}Ошибка создания временного файла${DEFAULT}"; pause; return 1; }
        trap 'rm -f "$temp_file"' EXIT

        # Переписываем все строки, кроме удаляемой
        local count=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
                echo "$line" >> "$temp_file"
            else
                if [ $count -ne $idx ]; then
                    echo "$line" >> "$temp_file"
                fi
                ((count++))
            fi
        done < "$CRON_FILE"

        if safe_write "$CRON_FILE" "$temp_file"; then
            :
        else
            echo -e "${RED}Не удалось удалить задачу${DEFAULT}"
        fi
        rm -f "$temp_file"
        trap - EXIT
    fi

    pause
}


# Вспомогательные функции для меню

# Просмотр текущих задач
view_tasks() {
    if [ ! -f "$CRON_FILE" ]; then
        echo -e "${RED}Файл $CRON_FILE не найден${DEFAULT}"
        pause
        return 1
    fi

    echo -e "${GREEN}Текущие задачи cron:${DEFAULT}"
    echo "-----------------------------------"
    # Исключаем комментарии и пустые строки, нумеруем вывод
    grep -v "^#" "$CRON_FILE" | grep -v "^$" | nl -w2 -s') '
    if [ ${PIPESTATUS[0]} -ne 0 ] || [ -z "$(grep -v "^#" "$CRON_FILE" | grep -v "^$")" ]; then
        echo -e "${YELLOW}Нет активных задач${DEFAULT}"
    fi
    echo "-----------------------------------"
    pause
}

# Проверка статуса cron сервиса
check_cron_status() {
    echo -e "${GREEN}Статус cron сервиса:${DEFAULT}"
    echo "-----------------------------------"

    local service_name=""
    if systemctl list-units --full -all | grep -Fq 'cron.service'; then
        service_name="cron"
    elif systemctl list-units --full -all | grep -Fq 'crond.service'; then
        service_name="crond"
    fi

    if [ -n "$service_name" ]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "Статус: ${GREEN}Активен${DEFAULT} ✓"
        else
            echo -e "Статус: ${RED}Не активен${DEFAULT} ✗"
        fi

        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            echo -e "Автозапуск: ${GREEN}Включен${DEFAULT}"
        else
            echo -e "Автозапуск: ${RED}Отключен${DEFAULT}"
        fi

        echo "-----------------------------------"
        systemctl status "$service_name" --no-pager -l 2>/dev/null
    else
        echo -e "${RED}Сервис cron не найден${DEFAULT}"
    fi
    echo "-----------------------------------"
    pause
}

# Меню проверки синтаксиса
check_syntax_menu() {
    echo -e "${GREEN}Проверка синтаксиса задачи${DEFAULT}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${DEFAULT}"
    echo -e "${GREEN}Текущие задачи для примера:${DEFAULT}"
    echo "-----------------------------------"

    if [ -f "$CRON_FILE" ]; then
        grep -v "^#" "$CRON_FILE" | grep -v "^$" | nl -w2 -s') ' | head -5
        echo "-----------------------------------"
    fi

    show_task_format_info
    echo

    read -r -e -p "Введите задачу для проверки (Enter - отмена): " task_to_check

    if [ -n "$task_to_check" ]; then
        check_syntax "$task_to_check"
    else
        echo -e "${YELLOW}Проверка отменена${DEFAULT}"
    fi
    pause
}


# Инициализация и проверка окружения

# Убеждаемся, что файл /etc/crontab существует, иначе создаём с базовым содержимым
ensure_cron_file() {
    if [ ! -f "$CRON_FILE" ]; then
        echo -e "${YELLOW}Файл $CRON_FILE не найден, создаём...${DEFAULT}"
        sudo bash -c "cat > $CRON_FILE" <<EOF
# /etc/crontab: system-wide crontab
# Unlike any other crontab you don't have to run the 'crontab'
# command to install the new version when you edit this file
# and files in /etc/cron.d. These files also have username fields,
# that none of the other crontabs do.

SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name command to be executed
EOF
        echo -e "${GREEN}Файл создан.${DEFAULT}"
    fi
}

# Предупреждение, если скрипт запущен не от root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}╔════════════════════════════════════════════════╗${DEFAULT}"
    echo -e "${YELLOW}║  ВНИМАНИЕ: Скрипт запущен без прав root      ║${DEFAULT}"
    echo -e "${YELLOW}║  Некоторые функции могут быть недоступны     ║${DEFAULT}"
    echo -e "${YELLOW}║  Для полного функционала используйте:        ║${DEFAULT}"
    echo -e "${YELLOW}║  sudo $0                                     ║${DEFAULT}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════╝${DEFAULT}"
    echo
    sleep 2
fi

# Гарантируем наличие файла crontab
ensure_cron_file


# Основной цикл программы
while true; do
    show_menu
    read -r -e -p "Выберите пункт меню: " choice

    # Очистка ввода от возможных символов возврата каретки и лишних пробелов
    choice=$(echo "$choice" | tr -d '\r' | xargs)

    case $choice in
        1)
            view_tasks
            ;;
        2)
            add_task
            ;;
        3)
            edit_task
            ;;
        4)
            delete_task
            ;;
        5)
            check_syntax_menu
            ;;
        6)
            check_cron_status
            ;;
        0)
            echo -e "${GREEN}До свидания!${DEFAULT}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Пожалуйста, выберите 0-6${DEFAULT}"
            pause
            ;;
    esac
done
