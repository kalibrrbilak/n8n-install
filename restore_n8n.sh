#!/bin/bash
# ============================================================
# Скрипт восстановления n8n из резервной копии
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

# ============================================================
# Проверка аргументов
# ============================================================

if [ -z "$1" ]; then
    log_error "Использование: $0 <путь_к_бэкапу>"
    echo ""
    echo "Доступные бэкапы:"
    ls -lh "$SCRIPT_DIR/backups/" 2>/dev/null | grep "n8n_backup_" || echo "  Нет бэкапов"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Файл бэкапа не найден: $BACKUP_FILE"
    exit 1
fi

# ============================================================
# Начало восстановления
# ============================================================

log_info "=========================================="
log_info "    Восстановление n8n из бэкапа"
log_info "=========================================="
log_info "Бэкап: $(basename $BACKUP_FILE)"

# Подтверждение от пользователя
log_warning "ВНИМАНИЕ! Все текущие данные будут заменены!"
read -p "Продолжить? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Восстановление отменено"
    exit 0
fi

send_telegram "🔄 *Начало восстановления n8n*

📁 Файл: \`$(basename $BACKUP_FILE)\`"

# ============================================================
# Остановка контейнеров
# ============================================================

log_info "Остановка контейнеров..."
docker compose down || docker-compose down

# ============================================================
# Создание резервной копии текущего состояния
# ============================================================

log_info "Создание резервной копии текущего состояния (на всякий случай)..."
if [ -f "$SCRIPT_DIR/backup_n8n.sh" ]; then
    "$SCRIPT_DIR/backup_n8n.sh" > /dev/null 2>&1 || log_warning "Не удалось создать бэкап текущего состояния"
fi

# ============================================================
# Распаковка бэкапа
# ============================================================

RESTORE_DIR=$(mktemp -d)
log_info "Временная директория: $RESTORE_DIR"

# Проверка формата файла
if [[ "$BACKUP_FILE" == *.enc ]]; then
    # Зашифрованный бэкап
    log_info "Расшифровка бэкапа..."

    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        log_error "N8N_ENCRYPTION_KEY не задан в .env. Невозможно расшифровать бэкап."
        rm -rf "$RESTORE_DIR"
        exit 1
    fi

    if ! command -v openssl &>/dev/null; then
        log_error "openssl не установлен"
        rm -rf "$RESTORE_DIR"
        exit 1
    fi

    DECRYPTED_FILE="$RESTORE_DIR/backup.tar.gz"
    openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 \
        -in "$BACKUP_FILE" \
        -out "$DECRYPTED_FILE" \
        -pass pass:"$N8N_ENCRYPTION_KEY"

    if [ ! -s "$DECRYPTED_FILE" ]; then
        log_error "Ошибка расшифровки. Проверьте N8N_ENCRYPTION_KEY."
        rm -rf "$RESTORE_DIR"
        exit 1
    fi

    ARCHIVE_FILE="$DECRYPTED_FILE"
else
    # Незашифрованный бэкап
    ARCHIVE_FILE="$BACKUP_FILE"
fi

log_info "Распаковка архива..."
cd "$RESTORE_DIR"
tar -xzf "$ARCHIVE_FILE"

# Найти директорию с данными
BACKUP_DATA_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "n8n_backup_*" | head -1)

if [ -z "$BACKUP_DATA_DIR" ]; then
    log_error "Не удалось найти данные в архиве"
    rm -rf "$RESTORE_DIR"
    exit 1
fi

log_success "Архив распакован: $BACKUP_DATA_DIR"

# ============================================================
# Восстановление PostgreSQL
# ============================================================

log_info "Запуск PostgreSQL для восстановления..."
docker compose up -d n8n-postgres

# Ожидание запуска PostgreSQL
sleep 10

log_info "Восстановление базы данных PostgreSQL..."

POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"

if [ -f "$BACKUP_DATA_DIR/database.sql" ]; then
    # Удаление существующих подключений
    docker exec n8n-postgres psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();" 2>/dev/null || true

    # Удаление и пересоздание базы
    docker exec n8n-postgres dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" 2>/dev/null || true
    docker exec n8n-postgres createdb -U "$POSTGRES_USER" "$POSTGRES_DB"

    # Восстановление дампа
    docker exec -i n8n-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$BACKUP_DATA_DIR/database.sql"

    log_success "База данных восстановлена"
else
    log_warning "Дамп базы данных не найден в бэкапе"
fi

# ============================================================
# Восстановление конфигурации n8n
# ============================================================

log_info "Восстановление конфигурации n8n..."

if [ -d "$BACKUP_DATA_DIR/n8n_data" ]; then
    # Удаление текущих данных
    docker volume rm n8n_data 2>/dev/null || true
    docker volume create n8n_data

    # Запуск временного контейнера для копирования
    docker run --rm -v n8n_data:/restore -v "$BACKUP_DATA_DIR/n8n_data":/backup alpine sh -c "cp -r /backup/. /restore/"

    log_success "Конфигурация n8n восстановлена"
else
    log_warning "Конфигурация n8n не найдена в бэкапе"
fi

# ============================================================
# Восстановление .env
# ============================================================

if [ -f "$BACKUP_DATA_DIR/.env" ]; then
    log_info "Найден .env в бэкапе. Хотите восстановить его?"
    read -p "Восстановить .env? (yes/no): " RESTORE_ENV

    if [ "$RESTORE_ENV" = "yes" ]; then
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.before_restore"
        cp "$BACKUP_DATA_DIR/.env" "$SCRIPT_DIR/.env"
        log_success ".env восстановлен (старый сохранен как .env.before_restore)"
    else
        log_info ".env не восстановлен (используется текущий)"
    fi
fi

# ============================================================
# Очистка
# ============================================================

log_info "Очистка временных файлов..."
rm -rf "$RESTORE_DIR"

# ============================================================
# Запуск всех контейнеров
# ============================================================

log_info "Запуск всех контейнеров..."
docker compose up -d

# Ожидание запуска n8n
log_info "Ожидание запуска n8n (до 60 секунд)..."
sleep 10

for i in {1..25}; do
    sleep 2
    if docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log_success "n8n запущен!"
        break
    fi
    echo -n "."
done
echo ""

# ============================================================
# Проверка статуса
# ============================================================

STATUS=$(docker compose ps 2>/dev/null | grep -c "Up" || echo "0")

log_info "=========================================="
log_success "    Восстановление завершено!"
log_info "=========================================="
log_info "Контейнеров запущено: $STATUS"
log_info "Проверьте работу n8n: https://${DOMAIN:-n8n}"

send_telegram "✅ *Восстановление n8n завершено!*

📁 Восстановлено из: \`$(basename $BACKUP_FILE)\`
✅ Контейнеров запущено: $STATUS

🔗 Проверьте: https://${DOMAIN:-n8n}"

log_success "Готово!"
