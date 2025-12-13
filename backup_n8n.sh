#!/bin/bash
# ============================================================
# Скрипт резервного копирования n8n
# Создаёт зашифрованный бэкап PostgreSQL и конфигурации
# ============================================================

set -e

# Определение директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

# Загрузка переменных окружения
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Конфигурация
BACKUP_DIR="$SCRIPT_DIR/backups"
BACKUP_NAME="n8n_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Создание директорий
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_PATH"

# Функция отправки в Telegram
send_telegram() {
    local message="$1"
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_USER_ID}" \
            -d "text=${message}" \
            -d "parse_mode=Markdown" > /dev/null 2>&1 || true
    fi
}

# Функция очистки при ошибке
cleanup_on_error() {
    log_error "Ошибка во время резервного копирования"
    rm -rf "$BACKUP_PATH" 2>/dev/null || true
    send_telegram "❌ Ошибка создания бэкапа n8n"
    exit 1
}

trap cleanup_on_error ERR

# ============================================================
# Начало резервного копирования
# ============================================================

log_info "=========================================="
log_info "    Резервное копирование n8n"
log_info "=========================================="

# Проверка что Docker запущен
if ! systemctl is-active --quiet docker 2>/dev/null; then
    log_error "Docker не запущен. Запустите его: systemctl start docker"
    send_telegram "❌ Ошибка бэкапа: Docker не запущен"
    exit 1
fi

# Проверка что контейнеры запущены
if ! docker ps --format '{{.Names}}' | grep -q "^n8n-postgres$"; then
    log_error "Контейнер n8n-postgres не запущен"
    send_telegram "❌ Ошибка бэкапа: контейнер PostgreSQL не запущен"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
    log_warning "Контейнер n8n не запущен (бэкап всё равно будет создан)"
fi

# ============================================================
# Бэкап PostgreSQL
# ============================================================

log_info "Создание дампа PostgreSQL..."

POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"

DUMP_ERROR=$(docker exec n8n-postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" 2>&1 > "$BACKUP_PATH/database.sql")
DUMP_EXIT=$?

if [ $DUMP_EXIT -ne 0 ]; then
    log_error "Не удалось создать дамп PostgreSQL: $DUMP_ERROR"
    send_telegram "❌ Ошибка создания дампа PostgreSQL"
    rm -rf "$BACKUP_PATH"
    exit 1
fi

# Проверка что дамп не пустой
if [ ! -s "$BACKUP_PATH/database.sql" ]; then
    log_error "Дамп PostgreSQL пустой"
    send_telegram "❌ Ошибка: дамп PostgreSQL пустой"
    rm -rf "$BACKUP_PATH"
    exit 1
fi

DB_SIZE=$(du -h "$BACKUP_PATH/database.sql" | cut -f1)
log_success "Дамп PostgreSQL создан ($DB_SIZE)"

# ============================================================
# Бэкап конфигурации n8n
# ============================================================

log_info "Копирование конфигурации n8n..."

# Проверяем что контейнер n8n существует
if ! docker ps -a --format '{{.Names}}' | grep -q "^n8n$"; then
    log_warning "Контейнер n8n не существует, пропускаем копирование конфигурации"
else
    CP_ERROR=$(docker cp n8n:/home/node/.n8n "$BACKUP_PATH/n8n_data" 2>&1)
    CP_EXIT=$?

    if [ $CP_EXIT -ne 0 ]; then
        log_warning "Не удалось скопировать конфигурацию n8n: $CP_ERROR"
        log_warning "Продолжаем создание бэкапа без конфигурации n8n"
    else
        # Проверка что данные скопированы
        if [ -d "$BACKUP_PATH/n8n_data" ] && [ "$(ls -A $BACKUP_PATH/n8n_data 2>/dev/null)" ]; then
            N8N_SIZE=$(du -sh "$BACKUP_PATH/n8n_data" 2>/dev/null | cut -f1)
            log_success "Конфигурация n8n скопирована ($N8N_SIZE)"
        else
            log_warning "Директория конфигурации n8n пуста или не существует"
        fi
    fi
fi

# ============================================================
# Бэкап .env
# ============================================================

log_info "Копирование .env..."

if [ -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env" "$BACKUP_PATH/.env"
    log_success ".env скопирован"
else
    log_warning ".env не найден"
fi

# ============================================================
# Бэкап docker-compose.yml
# ============================================================

log_info "Копирование docker-compose.yml..."

if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/docker-compose.yml" "$BACKUP_PATH/docker-compose.yml"
    log_success "docker-compose.yml скопирован"
fi

# ============================================================
# Информация о версиях
# ============================================================

log_info "Сохранение информации о версиях..."

{
    echo "Backup created: $(date)"
    echo "n8n version: $(docker exec n8n n8n --version 2>/dev/null || echo 'N/A')"
    echo "Docker version: $(docker --version 2>/dev/null || echo 'N/A')"
    echo "PostgreSQL version: $(docker exec n8n-postgres psql --version 2>/dev/null || echo 'N/A')"
    echo "Redis version: $(docker exec n8n-redis redis-server --version 2>/dev/null || echo 'N/A')"
} > "$BACKUP_PATH/versions.txt"

# ============================================================
# Архивирование
# ============================================================

log_info "Создание архива..."

cd "$BACKUP_DIR" || {
    log_error "Не удалось перейти в директорию $BACKUP_DIR"
    send_telegram "❌ Ошибка создания архива"
    exit 1
}

TAR_ERROR=$(tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" 2>&1)
TAR_EXIT=$?

if [ $TAR_EXIT -ne 0 ]; then
    log_error "Не удалось создать архив: $TAR_ERROR"
    send_telegram "❌ Ошибка создания tar архива"
    rm -rf "$BACKUP_NAME"
    exit 1
fi

# Проверка что архив создан и не пустой
if [ ! -s "${BACKUP_NAME}.tar.gz" ]; then
    log_error "Архив пустой или не создан"
    send_telegram "❌ Ошибка: архив бэкапа пустой"
    rm -rf "$BACKUP_NAME"
    exit 1
fi

ARCHIVE_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
log_success "Архив создан ($ARCHIVE_SIZE)"

# ============================================================
# Шифрование (опционально)
# ============================================================

if [ -n "$N8N_ENCRYPTION_KEY" ]; then
    log_info "Шифрование архива..."

    # Проверка что openssl установлен
    if ! command -v openssl &>/dev/null; then
        log_error "openssl не установлен, шифрование невозможно"
        FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
        log_warning "Бэкап сохранён БЕЗ шифрования"
    else
        ENC_ERROR=$(openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
            -in "${BACKUP_NAME}.tar.gz" \
            -out "${BACKUP_NAME}.tar.gz.enc" \
            -pass pass:"$N8N_ENCRYPTION_KEY" 2>&1)
        ENC_EXIT=$?

        if [ $ENC_EXIT -ne 0 ]; then
            log_error "Не удалось зашифровать архив: $ENC_ERROR"
            FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
            log_warning "Бэкап сохранён БЕЗ шифрования"
        else
            # Проверка что зашифрованный файл создан
            if [ ! -s "${BACKUP_NAME}.tar.gz.enc" ]; then
                log_error "Зашифрованный файл пустой или не создан"
                FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
                log_warning "Бэкап сохранён БЕЗ шифрования"
            else
                rm "${BACKUP_NAME}.tar.gz"
                FINAL_BACKUP="${BACKUP_NAME}.tar.gz.enc"
                log_success "Архив зашифрован"
            fi
        fi
    fi
else
    FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
    log_warning "Шифрование пропущено (N8N_ENCRYPTION_KEY не задан)"
fi

# Удаление временной директории
rm -rf "$BACKUP_NAME"

# ============================================================
# Удаление старых бэкапов
# ============================================================

log_info "Удаление бэкапов старше $RETENTION_DAYS дней..."

OLD_BACKUPS=$(find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)
find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

if [ "$OLD_BACKUPS" -gt 0 ]; then
    log_success "Удалено старых бэкапов: $OLD_BACKUPS"
fi

# ============================================================
# Статистика
# ============================================================

FINAL_SIZE=$(du -h "$BACKUP_DIR/$FINAL_BACKUP" | cut -f1)
TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

log_info "=========================================="
log_success "    Резервное копирование завершено!"
log_info "=========================================="
log_info "Файл: $FINAL_BACKUP"
log_info "Размер: $FINAL_SIZE"
log_info "Всего бэкапов: $TOTAL_BACKUPS"
log_info "Общий размер: $TOTAL_SIZE"

send_telegram "✅ *Бэкап n8n создан*

📁 Файл: \`$FINAL_BACKUP\`
📊 Размер: $FINAL_SIZE
📚 Всего бэкапов: $TOTAL_BACKUPS
💾 Общий размер: $TOTAL_SIZE"

# Вывод пути к бэкапу (для использования в скриптах)
echo "$BACKUP_DIR/$FINAL_BACKUP"
