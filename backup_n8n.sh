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

# ============================================================
# Бэкап PostgreSQL
# ============================================================

log_info "Создание дампа PostgreSQL..."

POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"

if docker exec n8n-postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$BACKUP_PATH/database.sql" 2>/dev/null; then
    DB_SIZE=$(du -h "$BACKUP_PATH/database.sql" | cut -f1)
    log_success "Дамп PostgreSQL создан ($DB_SIZE)"
else
    log_warning "Не удалось создать дамп PostgreSQL"
fi

# ============================================================
# Бэкап конфигурации n8n
# ============================================================

log_info "Копирование конфигурации n8n..."

if docker cp n8n:/home/node/.n8n "$BACKUP_PATH/n8n_data" 2>/dev/null; then
    N8N_SIZE=$(du -sh "$BACKUP_PATH/n8n_data" 2>/dev/null | cut -f1)
    log_success "Конфигурация n8n скопирована ($N8N_SIZE)"
else
    log_warning "Не удалось скопировать конфигурацию n8n"
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

cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

ARCHIVE_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
log_success "Архив создан ($ARCHIVE_SIZE)"

# ============================================================
# Шифрование (опционально)
# ============================================================

if [ -n "$N8N_ENCRYPTION_KEY" ]; then
    log_info "Шифрование архива..."

    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "${BACKUP_NAME}.tar.gz" \
        -out "${BACKUP_NAME}.tar.gz.enc" \
        -pass pass:"$N8N_ENCRYPTION_KEY"

    rm "${BACKUP_NAME}.tar.gz"
    FINAL_BACKUP="${BACKUP_NAME}.tar.gz.enc"
    log_success "Архив зашифрован"
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
