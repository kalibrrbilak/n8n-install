#!/bin/bash
# ============================================================
# n8n Auto Install Script v2.0
# Поддерживает Ubuntu 22.04 LTS
# Docker Engine, n8n 2.0+, PostgreSQL 16, Redis 7
# Proxy, Gemini CLI, Execute Command Support
# ============================================================

set -e

# Директории и переменные
INSTALL_DIR="/opt/main"
CUSTOM_DIR="/opt/n8n_custom"
GEMINI_DIR="/opt/gemini"
LOG_FILE="/tmp/n8n_install_$(date +%Y%m%d_%H%M%S).log"
REPO_URL="https://github.com/kalibrrbilak/n8n-install.git"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Символы для статусов
CHECK="✓"
CROSS="✗"
ARROW="→"
GEAR="⚙"
ROCKET="🚀"
LOCK="🔒"
BOT="🤖"
GLOBE="🌐"

# ============================================================
# Функции логирования
# ============================================================
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_to_file "=== $1 ==="
}

print_step() {
    echo -e "${BLUE}${ARROW}${NC} ${BOLD}$1${NC}"
    log_to_file "[STEP] $1"
}

print_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
    log_to_file "[OK] $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
    log_to_file "[WARN] $1"
}

print_error() {
    echo -e "${RED}${CROSS}${NC} $1"
    log_to_file "[ERROR] $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log_to_file "[INFO] $1"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p "$pid" > /dev/null 2>&1; do
        for i in $(seq 0 3); do
            printf "\r  ${CYAN}%c${NC} " "${spinstr:$i:1}"
            sleep $delay
        done
    done
    printf "\r"
}

# ============================================================
# Функции валидации
# ============================================================
validate_proxy_format() {
    local proxy="$1"
    if [[ -z "$proxy" ]]; then
        return 0  # Пустой прокси допустим
    fi

    # Формат: http://login:password@ip:port или http://ip:port
    if [[ "$proxy" =~ ^https?://([^:]+:[^@]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]] || \
       [[ "$proxy" =~ ^https?://([^:]+:[^@]+@)?[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24
}

# ============================================================
# Начало скрипта
# ============================================================
clear
echo ""
echo -e "${MAGENTA}${BOLD}"
cat << 'BANNER'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║     ███╗   ██╗ █████╗ ███╗   ██╗                          ║
    ║     ████╗  ██║██╔══██╗████╗  ██║                          ║
    ║     ██╔██╗ ██║╚█████╔╝██╔██╗ ██║  Auto Install v2.0       ║
    ║     ██║╚██╗██║██╔══██╗██║╚██╗██║  Docker + AI + Proxy     ║
    ║     ██║ ╚████║╚█████╔╝██║ ╚████║                          ║
    ║     ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝                          ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "${CYAN}    Ubuntu 22.04 LTS | Docker | PostgreSQL 16 | Redis 7${NC}"
echo -e "${CYAN}    n8n 2.0+ | Gemini AI | Proxy Support | SSL${NC}"
echo ""

# ============================================================
# Шаг 1: Проверка прав root
# ============================================================
print_header "Шаг 1/7: Проверка системы"

if [[ $EUID -ne 0 ]]; then
    print_error "Скрипт должен быть запущен от root!"
    echo ""
    echo "Используйте: sudo bash install.sh"
    exit 1
fi
print_success "Права root подтверждены"

# Проверка ОС
if grep -qE "Ubuntu (22|24)" /etc/os-release 2>/dev/null; then
    OS_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    print_success "Операционная система: Ubuntu $OS_VERSION"
else
    print_warning "Рекомендуется Ubuntu 22.04 или 24.04"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Проверка памяти
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
if [[ $TOTAL_MEM -lt 1800 ]]; then
    print_warning "Доступно ${TOTAL_MEM}MB RAM (рекомендуется минимум 2GB)"
else
    print_success "RAM: ${TOTAL_MEM}MB"
fi

# Проверка диска
DISK_FREE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ $DISK_FREE -lt 15 ]]; then
    print_warning "Свободно ${DISK_FREE}GB диска (рекомендуется минимум 20GB)"
else
    print_success "Свободно на диске: ${DISK_FREE}GB"
fi

log_to_file "Логирование начато: $LOG_FILE"

# ============================================================
# Шаг 2: Настройка прокси (опционально)
# ============================================================
print_header "Шаг 2/7: Настройка прокси"

echo -e "${CYAN}Прокси используется для обхода ограничений и анонимности.${NC}"
echo -e "${CYAN}Формат: http://login:password@ip:port${NC}"
echo -e "${CYAN}Оставьте пустым для пропуска.${NC}"
echo ""

while true; do
    read -p "Введите прокси (или Enter для пропуска): " PROXY_URL

    if [[ -z "$PROXY_URL" ]]; then
        print_info "Прокси не используется"
        USE_PROXY="false"
        break
    fi

    if validate_proxy_format "$PROXY_URL"; then
        USE_PROXY="true"
        print_success "Прокси: $PROXY_URL"
        break
    else
        print_error "Неверный формат прокси. Пример: http://user:pass@192.168.1.1:8080"
    fi
done

# Применение прокси к системе
if [[ "$USE_PROXY" == "true" ]]; then
    print_step "Настройка системного прокси..."

    # Прокси для текущей сессии
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="localhost,127.0.0.1,::1"

    # Прокси для apt
    cat > /etc/apt/apt.conf.d/95proxy << EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF

    # Прокси для Docker daemon
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

    # Прокси для текущего пользователя
    cat >> /etc/environment << EOF
http_proxy="$PROXY_URL"
https_proxy="$PROXY_URL"
HTTP_PROXY="$PROXY_URL"
HTTPS_PROXY="$PROXY_URL"
no_proxy="localhost,127.0.0.1,::1"
NO_PROXY="localhost,127.0.0.1,::1"
EOF

    print_success "Системный прокси настроен"
fi

# ============================================================
# Шаг 3: Gemini API Key
# ============================================================
print_header "Шаг 3/7: Настройка Gemini AI"

echo -e "${CYAN}Gemini CLI позволяет использовать AI в n8n через Execute Command.${NC}"
echo -e "${CYAN}Получите API Key: https://aistudio.google.com/app/apikey${NC}"
echo ""

read -p "Введите Gemini API Key (или Enter для пропуска): " GEMINI_API_KEY

if [[ -n "$GEMINI_API_KEY" ]]; then
    INSTALL_GEMINI="true"
    # Маскируем ключ для вывода
    MASKED_KEY="${GEMINI_API_KEY:0:8}...${GEMINI_API_KEY: -4}"
    print_success "Gemini API Key: $MASKED_KEY"
else
    INSTALL_GEMINI="false"
    print_info "Gemini CLI не будет установлен"
fi

# ============================================================
# Шаг 4: Данные для Docker (Domain, Email, Passwords)
# ============================================================
print_header "Шаг 4/7: Настройка Docker и n8n"

# Домен
echo -e "${CYAN}Домен должен быть направлен на IP этого сервера (A-запись).${NC}"
echo ""
while true; do
    read -p "Введите домен для n8n (например, n8n.example.com): " DOMAIN
    if validate_domain "$DOMAIN"; then
        print_success "Домен: $DOMAIN"
        break
    else
        print_error "Неверный формат домена"
    fi
done

# Email для SSL
echo ""
while true; do
    read -p "Введите email для SSL сертификата: " EMAIL
    if validate_email "$EMAIL"; then
        print_success "Email: $EMAIL"
        break
    else
        print_error "Неверный формат email"
    fi
done

# Пароль PostgreSQL
echo ""
echo -e "${CYAN}Пароль для базы данных PostgreSQL.${NC}"
echo -e "${CYAN}Оставьте пустым для автогенерации.${NC}"
read -sp "Введите пароль PostgreSQL: " DB_PASSWORD
echo ""

if [[ -z "$DB_PASSWORD" ]]; then
    DB_PASSWORD=$(generate_password)
    print_success "Пароль PostgreSQL сгенерирован автоматически"
else
    print_success "Пароль PostgreSQL принят"
fi

# Генерация ключа шифрования
print_step "Генерация N8N_ENCRYPTION_KEY..."
ENCRYPTION_KEY=$(openssl rand -hex 32)
print_success "Ключ шифрования сгенерирован"

# ============================================================
# Шаг 5: Telegram бот
# ============================================================
print_header "Шаг 5/7: Настройка Telegram бота"

echo -e "${CYAN}Telegram бот для управления n8n (статус, обновления, бэкапы).${NC}"
echo -e "${CYAN}Создайте бота: https://t.me/BotFather${NC}"
echo ""

read -p "Введите Telegram Bot Token: " TG_BOT_TOKEN

if [[ -n "$TG_BOT_TOKEN" ]]; then
    read -p "Введите ваш Telegram User ID (получить: @userinfobot): " TG_USER_ID

    if [[ -n "$TG_USER_ID" ]]; then
        USE_TG_BOT="true"
        print_success "Telegram бот настроен"
    else
        USE_TG_BOT="false"
        print_warning "User ID не указан - бот отключён"
    fi
else
    USE_TG_BOT="false"
    print_info "Telegram бот не настроен"
fi

# ============================================================
# Шаг 6: Подтверждение и установка
# ============================================================
print_header "Шаг 6/7: Подтверждение конфигурации"

echo -e "${BOLD}Конфигурация установки:${NC}"
echo ""
echo -e "  ${GLOBE} Домен:           ${GREEN}$DOMAIN${NC}"
echo -e "  📧 Email:           ${GREEN}$EMAIL${NC}"
echo -e "  ${LOCK} PostgreSQL:      ${GREEN}Пароль задан${NC}"
echo -e "  🔐 Encryption Key:  ${GREEN}Сгенерирован${NC}"

if [[ "$USE_PROXY" == "true" ]]; then
    echo -e "  🌐 Прокси:          ${GREEN}Настроен${NC}"
else
    echo -e "  🌐 Прокси:          ${YELLOW}Отключён${NC}"
fi

if [[ "$INSTALL_GEMINI" == "true" ]]; then
    echo -e "  🤖 Gemini CLI:      ${GREEN}Будет установлен${NC}"
else
    echo -e "  🤖 Gemini CLI:      ${YELLOW}Пропущен${NC}"
fi

if [[ "$USE_TG_BOT" == "true" ]]; then
    echo -e "  ${BOT} Telegram бот:    ${GREEN}Настроен${NC}"
else
    echo -e "  ${BOT} Telegram бот:    ${YELLOW}Отключён${NC}"
fi

echo ""
echo -e "  📁 Директория:      ${CYAN}$INSTALL_DIR${NC}"
echo -e "  📁 Custom папка:    ${CYAN}$CUSTOM_DIR${NC}"
echo -e "  📝 Лог установки:   ${CYAN}$LOG_FILE${NC}"
echo ""

read -p "Начать установку? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Установка отменена"
    exit 0
fi

# ============================================================
# Шаг 7: Процесс установки
# ============================================================
print_header "Шаг 7/7: Установка компонентов"

# --- Обновление системы ---
print_step "Обновление системы..."
apt-get update -qq >> "$LOG_FILE" 2>&1 || true
apt-get upgrade -y -qq >> "$LOG_FILE" 2>&1 || true
print_success "Система обновлена"

# --- Установка зависимостей ---
print_step "Установка зависимостей..."
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    wget \
    unzip \
    openssl \
    software-properties-common >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    print_success "Зависимости установлены"
else
    print_error "Ошибка установки зависимостей"
    exit 1
fi

# --- Установка Node.js 20+ ---
print_step "Установка Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x 2>> "$LOG_FILE" | bash - >> "$LOG_FILE" 2>&1
apt-get install -y -qq nodejs >> "$LOG_FILE" 2>&1
NODE_VERSION=$(node --version 2>/dev/null || echo "N/A")
if [ "$NODE_VERSION" != "N/A" ]; then
    print_success "Node.js установлен: $NODE_VERSION"
else
    print_warning "Node.js не установлен, продолжаем..."
fi

# --- Установка Docker ---
print_step "Установка Docker Engine..."

# Удаление старых версий
print_info "  Удаление старых версий Docker..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y -qq $pkg >> "$LOG_FILE" 2>&1 || true
done

# Добавление репозитория Docker
print_info "  Добавление репозитория Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc 2>> "$LOG_FILE"
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq >> "$LOG_FILE" 2>&1

# Установка Docker
print_info "  Установка Docker CE (это может занять несколько минут)..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    print_error "Ошибка установки Docker"
    exit 1
fi

# Перезагрузка systemd для применения прокси
print_info "  Настройка Docker службы..."
systemctl daemon-reload >> "$LOG_FILE" 2>&1
systemctl enable docker >> "$LOG_FILE" 2>&1
systemctl restart docker >> "$LOG_FILE" 2>&1

# Ожидание запуска Docker
sleep 3

DOCKER_VERSION=$(docker --version 2>/dev/null || echo "N/A")
if [ "$DOCKER_VERSION" != "N/A" ]; then
    print_success "Docker установлен: $DOCKER_VERSION"
else
    print_error "Docker не установлен! Проверьте лог: $LOG_FILE"
    exit 1
fi

# Проверка Docker Compose plugin
COMPOSE_VERSION=$(docker compose version 2>/dev/null || echo "N/A")
if [ "$COMPOSE_VERSION" != "N/A" ]; then
    print_success "Docker Compose: $COMPOSE_VERSION"
else
    print_error "Docker Compose plugin не установлен!"
    exit 1
fi

# --- Добавление пользователя в группу docker ---
print_step "Настройка прав Docker..."
if [[ -n "$SUDO_USER" ]]; then
    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    print_success "Пользователь $SUDO_USER добавлен в группу docker"
else
    print_info "Запущено от root, группа docker не требуется"
fi

# --- Создание директорий ---
print_step "Создание директорий..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/backups"
mkdir -p "$CUSTOM_DIR"
chown -R 1000:1000 "$CUSTOM_DIR"
chmod 755 "$CUSTOM_DIR"
print_success "Директории созданы"

# --- Клонирование репозитория ---
print_step "Клонирование репозитория..."
{
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || true
} >> "$LOG_FILE" 2>&1
cd "$INSTALL_DIR"
print_success "Репозиторий подготовлен"

# --- Установка Gemini CLI ---
if [[ "$INSTALL_GEMINI" == "true" ]]; then
    print_step "Установка Gemini CLI..."
    {
        mkdir -p "$GEMINI_DIR"

        # Установка через npm глобально
        npm install -g @anthropic-ai/claude-code 2>/dev/null || true

        # Создание wrapper скрипта для Gemini
        cat > "$GEMINI_DIR/gemini-cli" << 'GEMINI_WRAPPER'
#!/bin/bash
# Gemini CLI Wrapper для n8n Execute Command
# Использование: gemini-cli "ваш промпт"

GEMINI_API_KEY="${GEMINI_API_KEY}"

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY not set"
    exit 1
fi

PROMPT="$*"

if [[ -z "$PROMPT" ]]; then
    echo "Usage: gemini-cli <prompt>"
    exit 1
fi

# Запрос к Gemini API
RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${GEMINI_API_KEY}" \
    -H 'Content-Type: application/json' \
    -d "{
        \"contents\": [{
            \"parts\": [{
                \"text\": \"${PROMPT}\"
            }]
        }],
        \"generationConfig\": {
            \"temperature\": 0.7,
            \"maxOutputTokens\": 2048
        }
    }" 2>/dev/null)

# Извлечение текста ответа
echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // "Error: No response"' 2>/dev/null || echo "$RESPONSE"
GEMINI_WRAPPER

        chmod +x "$GEMINI_DIR/gemini-cli"

        # Добавляем API ключ в wrapper
        sed -i "s/GEMINI_API_KEY=\"\${GEMINI_API_KEY}\"/GEMINI_API_KEY=\"$GEMINI_API_KEY\"/" "$GEMINI_DIR/gemini-cli"

        # Символическая ссылка в /usr/local/bin
        ln -sf "$GEMINI_DIR/gemini-cli" /usr/local/bin/gemini-cli

    } >> "$LOG_FILE" 2>&1
    print_success "Gemini CLI установлен в $GEMINI_DIR"
fi

# --- Создание .env файла ---
print_step "Создание конфигурации .env..."
cat > "$INSTALL_DIR/.env" << EOF
# ============================================================
# n8n Configuration v2.0
# Generated: $(date)
# ============================================================

# Domain & URL
DOMAIN=${DOMAIN}
N8N_HOST=${DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${DOMAIN}/
N8N_EDITOR_BASE_URL=https://${DOMAIN}/

# Security
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Database - PostgreSQL 16
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=n8n-postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n

# Redis 7
REDIS_HOST=n8n-redis
REDIS_PORT=6379
QUEUE_BULL_REDIS_HOST=n8n-redis
QUEUE_BULL_REDIS_PORT=6379

# Queue Mode for Performance
EXECUTIONS_MODE=queue

# SSL
SSL_EMAIL=${EMAIL}

# Timezone
GENERIC_TIMEZONE=Europe/Moscow
TZ=Europe/Moscow

# n8n Settings
N8N_METRICS=true
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_DIAGNOSTICS_ENABLED=false
N8N_PERSONALIZATION_ENABLED=false
N8N_HIRING_BANNER_ENABLED=false

# Execute Command Node - ENABLED
N8N_ALLOW_EXEC=true
N8N_COMMUNITY_PACKAGES_ENABLED=true
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

# Custom Files Directory
N8N_USER_FOLDER=/home/node/.n8n
N8N_CUSTOM_EXTENSIONS=/opt/n8n_custom

# Proxy Settings
EOF

if [[ "$USE_PROXY" == "true" ]]; then
    cat >> "$INSTALL_DIR/.env" << EOF
HTTP_PROXY=${PROXY_URL}
HTTPS_PROXY=${PROXY_URL}
GLOBAL_HTTP_PROXY=${PROXY_URL}
N8N_HTTP_PROXY=${PROXY_URL}
N8N_HTTPS_PROXY=${PROXY_URL}
NO_PROXY=localhost,127.0.0.1,n8n-postgres,n8n-redis,n8n-traefik
EOF
else
    echo "# Proxy not configured" >> "$INSTALL_DIR/.env"
fi

# Gemini
if [[ "$INSTALL_GEMINI" == "true" ]]; then
    cat >> "$INSTALL_DIR/.env" << EOF

# Gemini AI
GEMINI_API_KEY=${GEMINI_API_KEY}
GEMINI_CLI_PATH=/opt/gemini/gemini-cli
EOF
fi

# Telegram
cat >> "$INSTALL_DIR/.env" << EOF

# Telegram Bot
TG_BOT_TOKEN=${TG_BOT_TOKEN:-}
TG_USER_ID=${TG_USER_ID:-}
EOF

chmod 600 "$INSTALL_DIR/.env"
print_success "Конфигурация .env создана"

# --- Создание docker-compose.yml ---
print_step "Создание docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" << 'COMPOSE_EOF'
# ============================================================
# n8n Docker Compose v2.0
# PostgreSQL 16 + Redis 7 + Traefik SSL + n8n 2.0+
# ============================================================

services:
  # ==========================================================
  # n8n - Main Application
  # ==========================================================
  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      # Core Settings
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

      # Database
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      # Queue Mode with Redis
      - EXECUTIONS_MODE=${EXECUTIONS_MODE}
      - QUEUE_BULL_REDIS_HOST=${QUEUE_BULL_REDIS_HOST}
      - QUEUE_BULL_REDIS_PORT=${QUEUE_BULL_REDIS_PORT}

      # Execute Command Support
      - N8N_ALLOW_EXEC=${N8N_ALLOW_EXEC:-true}
      - N8N_COMMUNITY_PACKAGES_ENABLED=${N8N_COMMUNITY_PACKAGES_ENABLED:-true}

      # Execution Data
      - EXECUTIONS_DATA_SAVE_ON_ERROR=${EXECUTIONS_DATA_SAVE_ON_ERROR:-all}
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=${EXECUTIONS_DATA_SAVE_ON_SUCCESS:-all}
      - EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=${EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS:-true}

      # Timezone
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${TZ}

      # Logging
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=${N8N_LOG_OUTPUT:-console}
      - N8N_METRICS=${N8N_METRICS}
      - N8N_DIAGNOSTICS_ENABLED=${N8N_DIAGNOSTICS_ENABLED}

      # Proxy (if configured)
      - HTTP_PROXY=${HTTP_PROXY:-}
      - HTTPS_PROXY=${HTTPS_PROXY:-}
      - NO_PROXY=${NO_PROXY:-localhost,127.0.0.1}

      # Gemini (if configured)
      - GEMINI_API_KEY=${GEMINI_API_KEY:-}
      - GEMINI_CLI_PATH=${GEMINI_CLI_PATH:-}

    volumes:
      - n8n_data:/home/node/.n8n
      - /opt/n8n_custom:/opt/n8n_custom:rw
      - /opt/gemini:/opt/gemini:ro
      - ./logs:/logs
    depends_on:
      n8n-postgres:
        condition: service_healthy
      n8n-redis:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      - "traefik.http.routers.n8n-http.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.permanent=true"
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

  # ==========================================================
  # PostgreSQL 16 - Database
  # ==========================================================
  n8n-postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

  # ==========================================================
  # Redis 7 - Queue & Cache
  # ==========================================================
  n8n-redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --appendfsync everysec
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 64M

  # ==========================================================
  # Traefik - Reverse Proxy & SSL
  # ==========================================================
  n8n-traefik:
    image: traefik:v3.2
    container_name: n8n-traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=false"
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=n8n-network"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.http.tls=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--log.level=WARN"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ==========================================================
  # Telegram Bot - Management
  # ==========================================================
  n8n-bot:
    build:
      context: ./bot
      dockerfile: Dockerfile
    container_name: n8n-bot
    restart: unless-stopped
    environment:
      - TG_BOT_TOKEN=${TG_BOT_TOKEN}
      - TG_USER_ID=${TG_USER_ID}
      - N8N_DIR=/opt/main
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/main:/opt/main:ro
      - ./logs:/logs
    networks:
      - n8n-network
    depends_on:
      - n8n
    profiles:
      - bot

# ==========================================================
# Networks
# ==========================================================
networks:
  n8n-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

# ==========================================================
# Volumes
# ==========================================================
volumes:
  n8n_data:
    driver: local
  postgres_data:
    driver: local
  redis_data:
    driver: local
  traefik_certs:
    driver: local
COMPOSE_EOF

print_success "docker-compose.yml создан"

# --- Создание Dockerfile.n8n ---
print_step "Создание Dockerfile.n8n..."
cat > "$INSTALL_DIR/Dockerfile.n8n" << 'DOCKERFILE_EOF'
FROM n8nio/n8n:latest

USER root

# Установка дополнительных зависимостей
RUN apk add --no-cache \
    python3 \
    py3-pip \
    chromium \
    chromium-chromedriver \
    font-noto \
    font-noto-cjk \
    font-noto-emoji \
    ffmpeg \
    imagemagick \
    ghostscript \
    graphicsmagick \
    poppler-utils \
    tesseract-ocr \
    tesseract-ocr-data-rus \
    tesseract-ocr-data-eng \
    curl \
    jq \
    git \
    bash \
    coreutils \
    openssl

# Puppeteer конфигурация
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV CHROME_PATH=/usr/bin/chromium-browser

# n8n конфигурация
ENV N8N_USER_FOLDER=/home/node/.n8n

# Создание директории для custom расширений
RUN mkdir -p /opt/n8n_custom && chown node:node /opt/n8n_custom

USER node

WORKDIR /home/node

EXPOSE 5678

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD wget --spider -q http://localhost:5678/healthz || exit 1

CMD ["n8n"]
DOCKERFILE_EOF

print_success "Dockerfile.n8n создан"

# --- Создание бота ---
print_step "Создание Telegram бота..."
mkdir -p "$INSTALL_DIR/bot"

# package.json
cat > "$INSTALL_DIR/bot/package.json" << 'EOF'
{
  "name": "n8n-telegram-bot",
  "version": "2.0.0",
  "description": "Telegram bot for n8n management",
  "main": "bot.js",
  "scripts": {
    "start": "node bot.js"
  },
  "dependencies": {
    "node-telegram-bot-api": "^0.66.0"
  }
}
EOF

# Dockerfile для бота
cat > "$INSTALL_DIR/bot/Dockerfile" << 'EOF'
FROM node:20-alpine

RUN apk add --no-cache docker-cli bash curl

WORKDIR /app

COPY package.json ./
RUN npm install --production

COPY bot.js ./

CMD ["node", "bot.js"]
EOF

# bot.js
cat > "$INSTALL_DIR/bot/bot.js" << 'BOTJS_EOF'
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const fs = require('fs');

const BOT_TOKEN = process.env.TG_BOT_TOKEN;
const AUTHORIZED_USER = process.env.TG_USER_ID;
const N8N_DIR = process.env.N8N_DIR || '/opt/main';

if (!BOT_TOKEN || !AUTHORIZED_USER) {
    console.log('TG_BOT_TOKEN or TG_USER_ID not set, bot disabled');
    process.exit(0);
}

const bot = new TelegramBot(BOT_TOKEN, { polling: true });

const isAuthorized = (msg) => String(msg.from.id) === String(AUTHORIZED_USER);

const execCommand = (cmd, timeout = 60000) => {
    return new Promise((resolve, reject) => {
        exec(cmd, { timeout, maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
            if (error) reject(error);
            else resolve(stdout || stderr);
        });
    });
};

// /start и /help
bot.onText(/\/(start|help)/, (msg) => {
    if (!isAuthorized(msg)) return;
    const helpText = `
🤖 *n8n Management Bot v2.0*

📊 /status - Статус сервера
📋 /logs [N] - Последние N логов (по умолчанию 50)
🔄 /update - Обновить n8n
💾 /backup - Создать бэкап
♻️ /restart - Перезапустить n8n
🧹 /cleanup - Очистить Docker

📁 Директория: \`${N8N_DIR}\`
    `;
    bot.sendMessage(msg.chat.id, helpText, { parse_mode: 'Markdown' });
});

// /status
bot.onText(/\/status/, async (msg) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '⏳ Получаю статус...');

    try {
        const [uptime, containers, disk, memory, n8nVersion] = await Promise.all([
            execCommand('uptime -p').catch(() => 'N/A'),
            execCommand('docker ps --format "{{.Names}}: {{.Status}}"').catch(() => 'N/A'),
            execCommand("df -h / | tail -1 | awk '{print $5}'").catch(() => 'N/A'),
            execCommand("free -h | grep Mem | awk '{print $3\"/\"$2}'").catch(() => 'N/A'),
            execCommand('docker exec n8n n8n --version 2>/dev/null').catch(() => 'N/A')
        ]);

        const statusText = `
📊 *Статус сервера*

⏱ Uptime: ${uptime.trim()}
💾 Диск: ${disk.trim()}
🧠 RAM: ${memory.trim()}
📦 n8n: v${n8nVersion.trim()}

*Контейнеры:*
\`\`\`
${containers.trim()}
\`\`\`
        `;
        await bot.sendMessage(chatId, statusText, { parse_mode: 'Markdown' });
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// /logs
bot.onText(/\/logs(?:\s+(\d+))?/, async (msg, match) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;
    const lines = match[1] || 50;

    await bot.sendMessage(chatId, '⏳ Получаю логи...');

    try {
        const logs = await execCommand(`docker logs n8n --tail ${lines} 2>&1`);

        if (logs.length > 3900) {
            const logPath = `/tmp/n8n_logs_${Date.now()}.txt`;
            fs.writeFileSync(logPath, logs);
            await bot.sendDocument(chatId, logPath, { caption: `📋 Последние ${lines} строк логов` });
            fs.unlinkSync(logPath);
        } else {
            await bot.sendMessage(chatId, `📋 *Логи (${lines} строк):*\n\`\`\`\n${logs.substring(0, 3800)}\n\`\`\``, { parse_mode: 'Markdown' });
        }
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// /restart
bot.onText(/\/restart/, async (msg) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '🔄 Перезапускаю n8n...');

    try {
        await execCommand('docker restart n8n', 120000);
        await new Promise(resolve => setTimeout(resolve, 15000));
        const status = await execCommand('docker ps --filter name=n8n --format "{{.Status}}"');
        await bot.sendMessage(chatId, `✅ n8n перезапущен\nСтатус: ${status.trim()}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// /update
bot.onText(/\/update/, async (msg) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;

    try {
        await bot.sendMessage(chatId, '🔍 Проверяю версии...');

        const currentVersion = await execCommand('docker exec n8n n8n --version 2>/dev/null').catch(() => 'unknown');

        let latestVersion = 'unknown';
        try {
            const response = await execCommand('curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest');
            const data = JSON.parse(response);
            latestVersion = data.tag_name?.replace('n8n@', '') || 'unknown';
        } catch (e) {}

        await bot.sendMessage(chatId, `📦 Текущая: ${currentVersion.trim()}\n🆕 Последняя: ${latestVersion}`);

        if (currentVersion.trim() === latestVersion) {
            await bot.sendMessage(chatId, '✅ Уже установлена последняя версия!');
            return;
        }

        await bot.sendMessage(chatId, '💾 Создаю бэкап...');
        await execCommand(`cd ${N8N_DIR} && ./backup_n8n.sh`, 300000).catch(() => {});

        await bot.sendMessage(chatId, '🔄 Обновляю n8n... (5-10 минут)');
        await execCommand(`cd ${N8N_DIR} && docker compose build --no-cache n8n`, 600000);
        await execCommand(`cd ${N8N_DIR} && docker compose up -d n8n`, 120000);

        await new Promise(resolve => setTimeout(resolve, 20000));
        const newVersion = await execCommand('docker exec n8n n8n --version 2>/dev/null').catch(() => 'unknown');

        await execCommand('docker image prune -f', 60000);

        await bot.sendMessage(chatId, `✅ Обновление завершено!\n📦 Было: ${currentVersion.trim()}\n🆕 Стало: ${newVersion.trim()}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// /backup
bot.onText(/\/backup/, async (msg) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '💾 Создаю бэкап...');

    try {
        const result = await execCommand(`cd ${N8N_DIR} && ./backup_n8n.sh 2>&1`, 300000);
        await bot.sendMessage(chatId, `✅ Бэкап создан!\n${result.substring(0, 1000)}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// /cleanup
bot.onText(/\/cleanup/, async (msg) => {
    if (!isAuthorized(msg)) return;
    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '🧹 Очистка Docker...');

    try {
        await execCommand('docker system prune -f', 120000);
        const df = await execCommand("df -h / | tail -1 | awk '{print $4}'");
        await bot.sendMessage(chatId, `✅ Очистка завершена\nСвободно: ${df.trim()}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

bot.on('polling_error', (error) => {
    console.error('Polling error:', error.message);
});

console.log('🤖 n8n Telegram Bot v2.0 started');
console.log(`Authorized user: ${AUTHORIZED_USER}`);
BOTJS_EOF

print_success "Telegram бот создан"

# --- Создание скрипта обновления ---
print_step "Создание скрипта обновления..."

cat > "$INSTALL_DIR/update_n8n.sh" << 'UPDATE_EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source .env 2>/dev/null || true

LOG_FILE="./logs/update_$(date +%Y%m%d_%H%M%S).log"
mkdir -p ./logs

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

send_telegram() {
    [[ -n "$TG_BOT_TOKEN" && -n "$TG_USER_ID" ]] && \
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" -d "text=$1" -d "parse_mode=Markdown" > /dev/null 2>&1 || true
}

log "=== Начало обновления n8n ==="

CURRENT=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
LATEST=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | grep '"tag_name"' | sed -E 's/.*"n8n@([^"]+)".*/\1/' || echo "unknown")

log "Текущая: $CURRENT, Последняя: $LATEST"

if [ "$CURRENT" = "$LATEST" ]; then
    log "Уже последняя версия"
    send_telegram "✅ n8n v$CURRENT уже последняя версия"
    exit 0
fi

send_telegram "🔄 Обновление n8n: $CURRENT → $LATEST"

[[ -f ./backup_n8n.sh ]] && ./backup_n8n.sh || log "Бэкап пропущен"

log "Пересборка образа..."
docker compose build --no-cache n8n

log "Перезапуск..."
docker compose up -d n8n

sleep 30

NEW=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
log "Новая версия: $NEW"

docker image prune -f > /dev/null 2>&1

send_telegram "✅ n8n обновлён: $CURRENT → $NEW"
log "=== Обновление завершено ==="
UPDATE_EOF

chmod +x "$INSTALL_DIR/update_n8n.sh"

# Символическая ссылка в /usr/local/bin
ln -sf "$INSTALL_DIR/update_n8n.sh" /usr/local/bin/n8n-update
chmod +x /usr/local/bin/n8n-update

print_success "Скрипт обновления создан (/usr/local/bin/n8n-update)"

# --- Создание скрипта бэкапа ---
print_step "Создание скрипта бэкапа..."

cat > "$INSTALL_DIR/backup_n8n.sh" << 'BACKUP_EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source .env 2>/dev/null || true

BACKUP_DIR="./backups"
BACKUP_NAME="n8n_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

mkdir -p "$BACKUP_DIR" "$BACKUP_PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

send_telegram() {
    [[ -n "$TG_BOT_TOKEN" && -n "$TG_USER_ID" ]] && \
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" -d "text=$1" > /dev/null 2>&1 || true
}

log "=== Начало бэкапа ==="

# PostgreSQL дамп
log "Дамп PostgreSQL..."
docker exec n8n-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_PATH/database.sql"

# n8n data
log "Копирование данных n8n..."
docker cp n8n:/home/node/.n8n "$BACKUP_PATH/n8n_data" 2>/dev/null || true

# .env
cp .env "$BACKUP_PATH/.env" 2>/dev/null || true

# Архив
log "Создание архива..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

# Шифрование
if [[ -n "$N8N_ENCRYPTION_KEY" ]]; then
    log "Шифрование..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${BACKUP_NAME}.tar.gz" \
        -out "${BACKUP_NAME}.tar.gz.enc" \
        -pass pass:"$N8N_ENCRYPTION_KEY"
    rm "${BACKUP_NAME}.tar.gz"
    FINAL="${BACKUP_NAME}.tar.gz.enc"
else
    FINAL="${BACKUP_NAME}.tar.gz"
fi

rm -rf "$BACKUP_NAME"

# Очистка старых бэкапов (>7 дней)
find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" -mtime +7 -delete 2>/dev/null || true

SIZE=$(du -h "$FINAL" | cut -f1)
log "=== Бэкап завершён: $FINAL ($SIZE) ==="

send_telegram "💾 Бэкап создан: $FINAL ($SIZE)"
echo "$BACKUP_DIR/$FINAL"
BACKUP_EOF

chmod +x "$INSTALL_DIR/backup_n8n.sh"
print_success "Скрипт бэкапа создан"

# --- Сборка и запуск контейнеров ---
print_step "Сборка Docker образов (это может занять 5-10 минут)..."
cd "$INSTALL_DIR"

# Сборка образов
docker compose build >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    print_error "Ошибка сборки Docker образов! Проверьте лог: $LOG_FILE"
    exit 1
fi
print_success "Образы собраны"

print_step "Запуск контейнеров..."
if [[ "$USE_TG_BOT" == "true" ]]; then
    docker compose --profile bot up -d >> "$LOG_FILE" 2>&1
else
    docker compose up -d >> "$LOG_FILE" 2>&1
fi

if [ $? -ne 0 ]; then
    print_error "Ошибка запуска контейнеров! Проверьте лог: $LOG_FILE"
    exit 1
fi
print_success "Контейнеры запущены"

# Ожидание запуска n8n
print_step "Ожидание запуска n8n (до 3 минут)..."
n8n_started=false
for i in {1..36}; do
    if docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        n8n_started=true
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

if [[ "$n8n_started" == "true" ]]; then
    print_success "n8n запущен и готов к работе!"
else
    print_warning "n8n ещё запускается, проверьте через пару минут"
    print_info "Логи: docker compose logs -f n8n"
fi

# --- Настройка cron для бэкапов ---
print_step "Настройка автоматических бэкапов..."
(crontab -l 2>/dev/null | grep -v "backup_n8n.sh"; echo "0 3 * * * cd $INSTALL_DIR && ./backup_n8n.sh >> ./logs/backup.log 2>&1") | crontab - 2>/dev/null || true
print_success "Ежедневные бэкапы в 03:00"

# --- Отправка уведомления в Telegram ---
if [[ "$USE_TG_BOT" == "true" ]]; then
    print_step "Отправка уведомления в Telegram..."
    N8N_VERSION=$(docker exec n8n n8n --version 2>/dev/null || echo "N/A")

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=🚀 n8n успешно установлен!

🌐 URL: https://${DOMAIN}
📦 Версия: ${N8N_VERSION}
📁 Директория: ${INSTALL_DIR}

Используйте /help для команд бота." \
        -d "parse_mode=Markdown" > /dev/null 2>&1 && \
    print_success "Уведомление отправлено" || \
    print_warning "Не удалось отправить уведомление"
fi

# ============================================================
# Финальный вывод
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║          🎉 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! 🎉               ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BOLD}📋 Данные для входа:${NC}"
echo ""
echo -e "  ${GLOBE} URL:              ${GREEN}https://${DOMAIN}${NC}"
echo -e "  🔐 Encryption Key:  ${YELLOW}${ENCRYPTION_KEY}${NC}"
echo -e "  🗄️  PostgreSQL:      ${GREEN}n8n:${DB_PASSWORD}${NC}"
echo ""
echo -e "${BOLD}📁 Пути:${NC}"
echo ""
echo -e "  📂 Установка:       ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  📂 Custom папка:    ${CYAN}${CUSTOM_DIR}${NC}"
echo -e "  📂 Gemini CLI:      ${CYAN}${GEMINI_DIR}${NC}"
echo -e "  📝 Лог установки:   ${CYAN}${LOG_FILE}${NC}"
echo ""
echo -e "${BOLD}🛠️  Полезные команды:${NC}"
echo ""
echo "  cd $INSTALL_DIR"
echo "  docker compose ps          # Статус контейнеров"
echo "  docker compose logs -f n8n # Логи n8n"
echo "  n8n-update                 # Обновить n8n"
echo "  ./backup_n8n.sh            # Создать бэкап"
echo ""

if [[ "$INSTALL_GEMINI" == "true" ]]; then
    echo -e "${BOLD}🤖 Gemini CLI:${NC}"
    echo ""
    echo "  gemini-cli 'Ваш вопрос'   # Запрос к Gemini AI"
    echo ""
fi

if [[ "$USE_TG_BOT" == "true" ]]; then
    echo -e "${BOLD}${BOT} Telegram бот:${NC}"
    echo ""
    echo "  /status  - Статус сервера"
    echo "  /update  - Обновить n8n"
    echo "  /backup  - Создать бэкап"
    echo "  /logs    - Показать логи"
    echo ""
fi

echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Сохраните эти данные! Они не будут показаны снова.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Копируем финальный лог в директорию установки
cp "$LOG_FILE" "$INSTALL_DIR/logs/" 2>/dev/null || true

print_success "Готово! 🚀"
