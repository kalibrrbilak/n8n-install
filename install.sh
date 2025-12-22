#!/bin/bash
set -e

# ============================================================
# n8n Auto Install Script
# Поддерживает Ubuntu 22.04 / 24.04
# Docker Engine v29, n8n 2.0+
# ============================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка root
if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен быть запущен от root"
    exit 1
fi

# Проверка ОС
if ! grep -qE "Ubuntu (22|24)" /etc/os-release 2>/dev/null; then
    log_warning "Рекомендуется Ubuntu 22.04 или 24.04"
fi

echo ""
echo "=============================================="
echo "     n8n Auto Install - Docker Edition"
echo "=============================================="
echo ""

# Ввод данных
read -p "Домен для n8n (например, n8n.example.com): " DOMAIN
read -p "Домен для pgAdmin (например, pgadmin.example.com): " PGADMIN_DOMAIN
read -p "Домен для Redis Commander (например, redis.example.com): " REDIS_DOMAIN
read -p "Email для SSL сертификата и pgAdmin: " EMAIL
read -sp "Пароль PostgreSQL: " DB_PASSWORD
echo ""
read -p "Telegram Bot Token (или Enter для пропуска): " TG_BOT_TOKEN
read -p "Telegram User ID (или Enter для пропуска): " TG_USER_ID

# Валидация введённых данных
if [[ -z "$DOMAIN" ]]; then
    log_error "Домен для n8n не может быть пустым"
    exit 1
fi

if [[ -z "$PGADMIN_DOMAIN" ]]; then
    log_error "Домен для pgAdmin не может быть пустым"
    exit 1
fi

if [[ -z "$REDIS_DOMAIN" ]]; then
    log_error "Домен для Redis Commander не может быть пустым"
    exit 1
fi

if [[ -z "$EMAIL" ]]; then
    log_error "Email не может быть пустым"
    exit 1
fi

if [[ -z "$DB_PASSWORD" ]]; then
    log_error "Пароль базы данных не может быть пустым"
    exit 1
fi

if [[ -z "$TG_BOT_TOKEN" ]]; then
    log_warning "Telegram Bot Token не указан - бот не будет работать"
fi

if [[ -z "$TG_USER_ID" ]]; then
    log_warning "Telegram User ID не указан - бот не будет работать"
fi

# Проверка формата email
if ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    log_error "Некорректный формат email: $EMAIL"
    exit 1
fi

# Генерация паролей и ключей
log_info "Генерация паролей и ключей..."
if ! command -v openssl &>/dev/null; then
    log_error "openssl не установлен. Установите его: apt-get install openssl"
    exit 1
fi

ENCRYPTION_KEY=$(openssl rand -hex 32 2>&1)
if [[ $? -ne 0 ]] || [[ -z "$ENCRYPTION_KEY" ]]; then
    log_error "Не удалось сгенерировать ключ шифрования: $ENCRYPTION_KEY"
    exit 1
fi

REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25 2>&1)
if [[ $? -ne 0 ]] || [[ -z "$REDIS_PASSWORD" ]]; then
    log_error "Не удалось сгенерировать пароль Redis: $REDIS_PASSWORD"
    exit 1
fi

PGADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25 2>&1)
if [[ $? -ne 0 ]] || [[ -z "$PGADMIN_PASSWORD" ]]; then
    log_error "Не удалось сгенерировать пароль pgAdmin: $PGADMIN_PASSWORD"
    exit 1
fi

REDIS_UI_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25 2>&1)
if [[ $? -ne 0 ]] || [[ -z "$REDIS_UI_PASSWORD" ]]; then
    log_error "Не удалось сгенерировать пароль Redis UI: $REDIS_UI_PASSWORD"
    exit 1
fi

log_success "Все пароли и ключи сгенерированы"

# Директория установки
INSTALL_DIR="/opt/main"
REPO_URL="https://github.com/kalibrrbilak/n8n-install.git"

log_info "Обновление системы..."
if ! apt-get update -qq 2>&1; then
    log_error "Не удалось обновить список пакетов. Проверьте подключение к интернету и репозитории."
    exit 1
fi

if ! apt-get upgrade -y -qq 2>&1; then
    log_warning "Не удалось обновить некоторые пакеты, продолжаем..."
fi

log_info "Установка зависимостей..."
if ! apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq 2>&1; then
    log_error "Не удалось установить необходимые зависимости"
    exit 1
fi
log_success "Зависимости установлены"

# ============================================================
# Установка Docker Engine v29
# ============================================================
log_info "Установка Docker Engine..."

# Удаление старых версий
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y -qq $pkg 2>/dev/null || true
done

# Добавление репозитория Docker
log_info "Добавление репозитория Docker..."
if ! install -m 0755 -d /etc/apt/keyrings 2>&1; then
    log_error "Не удалось создать директорию /etc/apt/keyrings"
    exit 1
fi

if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc 2>&1; then
    log_error "Не удалось загрузить GPG ключ Docker. Проверьте подключение к интернету."
    exit 1
fi

if ! chmod a+r /etc/apt/keyrings/docker.asc 2>&1; then
    log_error "Не удалось установить права доступа на GPG ключ Docker"
    exit 1
fi

if ! echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null 2>&1; then
    log_error "Не удалось добавить репозиторий Docker"
    exit 1
fi

if ! apt-get update -qq 2>&1; then
    log_error "Не удалось обновить список пакетов после добавления репозитория Docker"
    exit 1
fi

# Установка Docker (последняя версия v29)
log_info "Установка Docker Engine..."
if ! apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1; then
    log_error "Не удалось установить Docker. Проверьте логи: journalctl -xe"
    exit 1
fi

# Проверка Docker
if ! docker --version &>/dev/null; then
    log_error "Docker установлен, но команда docker не работает"
    exit 1
fi
log_success "Docker установлен: $(docker --version)"

# Запуск Docker
log_info "Запуск Docker сервиса..."
if ! systemctl enable docker 2>&1; then
    log_error "Не удалось включить автозапуск Docker"
    exit 1
fi

if ! systemctl start docker 2>&1; then
    log_error "Не удалось запустить Docker. Проверьте статус: systemctl status docker"
    exit 1
fi

# Проверка что Docker работает
sleep 2
if ! systemctl is-active --quiet docker; then
    log_error "Docker сервис не запущен. Проверьте логи: journalctl -u docker"
    exit 1
fi
log_success "Docker сервис запущен"

# ============================================================
# Клонирование репозитория
# ============================================================
log_info "Подготовка директории установки..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Клонируем репозиторий или копируем локальные файлы
if command -v git &>/dev/null; then
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || {
        log_warning "Не удалось клонировать репозиторий, создаю файлы локально..."
    }
fi

cd "$INSTALL_DIR"

# ============================================================
# Создание .env файла
# ============================================================
log_info "Создание конфигурации..."
cat > "$INSTALL_DIR/.env" << EOF
# ============================================================
# n8n v3+ Полная конфигурация
# Создано автоматически при установке $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# ============================================================
# ДОМЕНЫ (обязательно настроить DNS A-записи!)
# ============================================================
DOMAIN=${DOMAIN}
PGADMIN_DOMAIN=${PGADMIN_DOMAIN}
REDIS_DOMAIN=${REDIS_DOMAIN}

# ============================================================
# SSL СЕРТИФИКАТЫ
# ============================================================
EMAIL=${EMAIL}

# ============================================================
# POSTGRESQL
# ============================================================
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n

# ============================================================
# PGADMIN (UI для PostgreSQL)
# Доступ: https://${PGADMIN_DOMAIN}
# ============================================================
PGADMIN_EMAIL=${EMAIL}
PGADMIN_PASSWORD=${PGADMIN_PASSWORD}

# ============================================================
# REDIS
# ============================================================
REDIS_PASSWORD=${REDIS_PASSWORD}

# Redis Commander UI (HTTP Basic Auth)
# Доступ: https://${REDIS_DOMAIN}
REDIS_UI_USER=admin
REDIS_UI_PASSWORD=${REDIS_UI_PASSWORD}

# ============================================================
# N8N - ОСНОВНЫЕ НАСТРОЙКИ
# ============================================================
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
WEBHOOK_URL=https://${DOMAIN}/

# ============================================================
# N8N - BINARY DATA MODE
# Где хранить файлы: filesystem (на диске) или database (в БД)
# Рекомендуется: filesystem для лучшей производительности
# ============================================================
N8N_BINARY_DATA_MODE=filesystem
N8N_DEFAULT_BINARY_DATA_MODE=filesystem

# ============================================================
# N8N - PROXY SETTINGS (для Traefik)
# ВАЖНО: для корректной работы с reverse proxy
# ============================================================
N8N_EXPRESS_TRUST_PROXY=true
N8N_TRUSTED_PROXIES=*
N8N_PROXY_HOPS=1

# ============================================================
# N8N - BASIC AUTH (дополнительная защита)
# Если включить, будет запрашивать логин/пароль ДО входа в n8n
# ============================================================
N8N_BASIC_AUTH_ACTIVE=false
# N8N_BASIC_AUTH_USER=admin
# N8N_BASIC_AUTH_PASSWORD=<пароль>

# ============================================================
# ВНЕШНИЙ PROXY (для n8n запросов наружу)
# Если n8n должен ходить в интернет через прокси
# Формат: http://user:pass@proxy-server:port
# ============================================================
PROXY_URL=

# Исключения для прокси (внутренние адреса Docker)
# ВАЖНО: эти адреса НЕ должны ходить через прокси
NO_PROXY=localhost,127.0.0.1,::1,.local,postgres,redis,pgadmin,traefik,n8n,n8n-postgres,n8n-redis,n8n-pgadmin,n8n-redis-commander,n8n-traefik

# ============================================================
# TELEGRAM BOT
# ============================================================
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_USER_ID=${TG_USER_ID}

# ============================================================
# РЕЗЕРВНОЕ КОПИРОВАНИЕ
# ============================================================
BACKUP_RETENTION_DAYS=7
BACKUP_SCHEDULE="0 2 * * *"

# ============================================================
# TIMEZONE (Екатеринбург)
# ============================================================
GENERIC_TIMEZONE=Asia/Yekaterinburg
TZ=Asia/Yekaterinburg

# ============================================================
# N8N - ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ
# ============================================================
N8N_METRICS=true
N8N_LOG_LEVEL=info
N8N_DIAGNOSTICS_ENABLED=false
N8N_PERSONALIZATION_ENABLED=false

# ============================================================
# QUEUE MODE (для высокой производительности)
# ============================================================
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=n8n-redis
QUEUE_BULL_REDIS_PORT=6379
EOF

chmod 600 "$INSTALL_DIR/.env"
log_success "Конфигурация создана"

# ============================================================
# Создание docker-compose.yml
# ============================================================
log_info "Создание docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  # ============================================================
  # n8n - Главное приложение
  # ============================================================
  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      # Домен и протокол
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=${WEBHOOK_URL}

      # Шифрование
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

      # База данных PostgreSQL
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

      # Queue mode с Redis
      - EXECUTIONS_MODE=${EXECUTIONS_MODE}
      - QUEUE_BULL_REDIS_HOST=${QUEUE_BULL_REDIS_HOST}
      - QUEUE_BULL_REDIS_PORT=${QUEUE_BULL_REDIS_PORT}
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}

      # Binary data
      - N8N_BINARY_DATA_MODE=${N8N_BINARY_DATA_MODE}
      - N8N_DEFAULT_BINARY_DATA_MODE=${N8N_DEFAULT_BINARY_DATA_MODE}

      # Proxy settings (для Traefik)
      - N8N_EXPRESS_TRUST_PROXY=${N8N_EXPRESS_TRUST_PROXY}
      - N8N_TRUSTED_PROXIES=${N8N_TRUSTED_PROXIES}
      - N8N_PROXY_HOPS=${N8N_PROXY_HOPS}

      # Basic Auth (опционально)
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER:-}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD:-}

      # Внешний прокси (опционально)
      - HTTP_PROXY=${PROXY_URL:-}
      - HTTPS_PROXY=${PROXY_URL:-}
      - NO_PROXY=${NO_PROXY}

      # Timezone
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${TZ}

      # Дополнительные настройки
      - N8N_METRICS=${N8N_METRICS}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_DIAGNOSTICS_ENABLED=${N8N_DIAGNOSTICS_ENABLED}
      - N8N_PERSONALIZATION_ENABLED=${N8N_PERSONALIZATION_ENABLED}

    volumes:
      - n8n_data:/home/node/.n8n
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

      # HTTP -> HTTPS redirect
      - "traefik.http.routers.n8n-http.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"

    networks:
      - n8n-network

    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # ============================================================
  # PostgreSQL - База данных
  # ============================================================
  n8n-postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=${TZ}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # ============================================================
  # pgAdmin - UI для PostgreSQL
  # ============================================================
  n8n-pgadmin:
    image: dpage/pgadmin4:latest
    container_name: n8n-pgadmin
    restart: unless-stopped
    environment:
      - PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}
      - PGADMIN_CONFIG_SERVER_MODE=False
      - PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False
      - TZ=${TZ}
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./configs/pgadmin/servers.json:/pgadmin4/servers.json:ro
    depends_on:
      - n8n-postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pgadmin.rule=Host(`${PGADMIN_DOMAIN}`)"
      - "traefik.http.routers.pgadmin.entrypoints=websecure"
      - "traefik.http.routers.pgadmin.tls.certresolver=letsencrypt"
      - "traefik.http.services.pgadmin.loadbalancer.server.port=80"
    networks:
      - n8n-network

  # ============================================================
  # Redis - Кэш и очередь
  # ============================================================
  n8n-redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    environment:
      - TZ=${TZ}
    volumes:
      - redis_data:/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "redis-cli", "--no-auth-warning", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  # ============================================================
  # Redis Commander - UI для Redis
  # ============================================================
  n8n-redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: n8n-redis-commander
    restart: unless-stopped
    environment:
      - REDIS_HOSTS=n8n:n8n-redis:6379:0:${REDIS_PASSWORD}
      - HTTP_USER=${REDIS_UI_USER}
      - HTTP_PASSWORD=${REDIS_UI_PASSWORD}
      - TZ=${TZ}
    depends_on:
      - n8n-redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.redis.rule=Host(`${REDIS_DOMAIN}`)"
      - "traefik.http.routers.redis.entrypoints=websecure"
      - "traefik.http.routers.redis.tls.certresolver=letsencrypt"
      - "traefik.http.services.redis.loadbalancer.server.port=8081"
    networks:
      - n8n-network

  # ============================================================
  # Traefik - Reverse Proxy + SSL
  # ============================================================
  n8n-traefik:
    image: traefik:v3.2
    container_name: n8n-traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--log.level=INFO"
    environment:
      - TZ=${TZ}
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

  # ============================================================
  # Telegram Bot - Администрирование
  # ============================================================
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
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - DOMAIN=${DOMAIN}
      - PGADMIN_DOMAIN=${PGADMIN_DOMAIN}
      - REDIS_DOMAIN=${REDIS_DOMAIN}
      - TZ=${TZ}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/main:/opt/main:ro
      - ./logs:/logs
    networks:
      - n8n-network
    depends_on:
      - n8n

networks:
  n8n-network:
    driver: bridge

volumes:
  n8n_data:
    driver: local
  postgres_data:
    driver: local
  redis_data:
    driver: local
  pgadmin_data:
    driver: local
  traefik_certs:
    driver: local
COMPOSE_EOF

log_success "docker-compose.yml создан"

# ============================================================
# Создание конфигурации pgAdmin
# ============================================================
log_info "Создание конфигурации pgAdmin..."
mkdir -p "$INSTALL_DIR/configs/pgadmin"

cat > "$INSTALL_DIR/configs/pgadmin/servers.json" << 'PGADMIN_EOF'
{
  "Servers": {
    "1": {
      "Name": "n8n PostgreSQL",
      "Group": "n8n",
      "Host": "n8n-postgres",
      "Port": 5432,
      "MaintenanceDB": "n8n",
      "Username": "n8n",
      "SSLMode": "prefer",
      "Comment": "n8n production database"
    }
  }
}
PGADMIN_EOF

log_success "Конфигурация pgAdmin создана"

# ============================================================
# Создание Dockerfile.n8n
# ============================================================
log_info "Создание Dockerfile.n8n..."
cat > "$INSTALL_DIR/Dockerfile.n8n" << 'DOCKERFILE_EOF'
FROM n8nio/n8n:latest

USER root

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚀 n8n SUPER BUILD - AI/ML + Автоматизация
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 👨‍💻 Автор: WebSansay
# 📱 Telegram: https://t.me/websansay
# 📢 Канал с автоматизациями: https://t.me/+p3VDHRpArOc5YzM6
# 💰 Поддержать проект: https://boosty.to/websansay
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "🚀 n8n SUPER BUILD - Начинаем сборку!" && \
    echo "👨‍💻 by WebSansay | TG: https://t.me/websansay" && \
    echo "📢 Канал: https://t.me/+p3VDHRpArOc5YzM6" && \
    echo "💰 Донаты: https://boosty.to/websansay" && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Системные пакеты (используем репозитории базового образа)
RUN apk add --no-cache \
  bash \
  curl \
  git \
  make \
  g++ \
  gcc \
  python3 \
  py3-pip \
  libffi-dev \
  yt-dlp \
  apache2-utils \
  ffmpeg \
  docker-cli \
  chromium \
  chromium-chromedriver \
  font-noto \
  font-noto-cjk \
  font-noto-emoji \
  imagemagick \
  ghostscript \
  graphicsmagick \
  poppler-utils \
  tesseract-ocr \
  tesseract-ocr-data-rus \
  tesseract-ocr-data-eng \
  jq

# (опционально) Создать группу docker и добавить пользователя node
ARG DOCKER_GID=999
RUN set -eux; \
  addgroup -S -g ${DOCKER_GID} docker || addgroup -S docker; \
  adduser node docker || true

# Чуть ускорим npm
RUN npm config set fund false && npm config set audit false

# npm-глобалки
RUN echo "" && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "📦 Устанавливаю 30+ npm пакетов для AI, ботов и автоматизации..." && \
    echo "⏱️  Это займёт 5-10 минут - идеальное время посетить наш канал! 😉" && \
    echo "📢 https://t.me/+p3VDHRpArOc5YzM6 - готовые сценарии и автоматизации!" && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo ""

RUN for pkg in \
    axios \
    node-fetch \
    form-data \
    moment \
    date-fns \
    lodash \
    fs-extra \
    path \
    csv-parser \
    xml2js \
    js-yaml \
    xlsx \
    jsonwebtoken \
    simple-oauth2 \
    uuid \
    openai \
    @tensorflow/tfjs-node \
    langchain \
    node-telegram-bot-api \
    discord.js \
    vk-io \
    whatsapp-web.js \
    fluent-ffmpeg \
    ffmpeg-static \
    google-tts-api \
    @vitalets/google-translate-token \
    node-wav \
    mongoose \
    ioredis \
    bcrypt \
    validator \
    joi \
    winston \
    dotenv \
    prom-client \
    node-downloader-helper \
    adm-zip \
    archiver \
  ; do \
    echo "🔧 Устанавливаем $pkg..." && npm install -g "$pkg" || echo "⚠️ Не удалось установить $pkg, продолжаем..."; \
  done

# Локально — для доступности в Code-нодах
RUN npm install oauth-1.0a

# Puppeteer конфигурация
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=false
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV CHROME_PATH=/usr/bin/chromium-browser

# n8n конфигурация
ENV N8N_USER_FOLDER=/home/node/.n8n

USER node

WORKDIR /home/node

# КРИТИЧНО: НЕ переопределяем CMD/ENTRYPOINT - используем из базового образа n8nio/n8n
# Базовый образ имеет правильный entrypoint для запуска n8n

RUN echo "" && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo "✅ n8n SUPER BUILD завершён успешно!" && \
    echo "" && \
    echo "🎉 Готовы к работе:" && \
    echo "   • OpenAI, TensorFlow, LangChain (AI/ML)" && \
    echo "   • Telegram, Discord, VK, WhatsApp боты" && \
    echo "   • FFmpeg, ImageMagick, Tesseract OCR" && \
    echo "   • Chromium + Puppeteer для автоматизации браузера" && \
    echo "   • И ещё 20+ библиотек!" && \
    echo "" && \
    echo "👨‍💻 Автор: WebSansay" && \
    echo "📱 Вопросы и помощь: https://t.me/websansay" && \
    echo "📢 Канал с готовыми сценариями: https://t.me/+p3VDHRpArOc5YzM6" && \
    echo "💰 Поддержать проект: https://boosty.to/websansay" && \
    echo "" && \
    echo "Понравилась сборка? Поддержи донатом! 🙏" && \
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
    echo ""
DOCKERFILE_EOF

log_success "Dockerfile.n8n создан"

# ============================================================
# Создание бота
# ============================================================
log_info "Создание Telegram бота..."
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

# bot.js - исправленный бот
cat > "$INSTALL_DIR/bot/bot.js" << 'BOTJS_EOF'
const TelegramBot = require('node-telegram-bot-api');
const { exec, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const BOT_TOKEN = process.env.TG_BOT_TOKEN;
const AUTHORIZED_USER = process.env.TG_USER_ID;
const N8N_DIR = process.env.N8N_DIR || '/opt/n8n';

if (!BOT_TOKEN || !AUTHORIZED_USER) {
    console.error('Missing TG_BOT_TOKEN or TG_USER_ID');
    process.exit(1);
}

const bot = new TelegramBot(BOT_TOKEN, { polling: true });

// Проверка авторизации
const isAuthorized = (msg) => {
    return String(msg.from.id) === String(AUTHORIZED_USER);
};

// Выполнение команды с таймаутом
const execCommand = (cmd, timeout = 60000) => {
    return new Promise((resolve, reject) => {
        exec(cmd, { timeout, maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
            if (error) {
                reject(error);
            } else {
                resolve(stdout || stderr);
            }
        });
    });
};

// Отправка длинного сообщения (разбивка на части)
const sendLongMessage = async (chatId, text, options = {}) => {
    const maxLength = 4000;
    if (text.length <= maxLength) {
        return bot.sendMessage(chatId, text, options);
    }

    const parts = [];
    for (let i = 0; i < text.length; i += maxLength) {
        parts.push(text.substring(i, i + maxLength));
    }

    for (const part of parts) {
        await bot.sendMessage(chatId, part, options);
    }
};

// /start
bot.onText(/\/start/, (msg) => {
    if (!isAuthorized(msg)) return;

    const helpText = `
*n8n Management Bot*

Доступные команды:
/status - Статус сервера и контейнеров
/logs - Последние логи n8n
/update - Обновить n8n до последней версии
/backups - Создать резервную копию
/restart - Перезапустить n8n
/help - Показать эту справку
    `;
    bot.sendMessage(msg.chat.id, helpText, { parse_mode: 'Markdown' });
});

// /help
bot.onText(/\/help/, (msg) => {
    if (!isAuthorized(msg)) return;
    bot.emit('text', msg, ['/start']);
});

// /status
bot.onText(/\/status/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '⏳ Получаю статус...');

    try {
        // Uptime
        const uptime = await execCommand('uptime -p');

        // Docker containers
        const containers = await execCommand('docker ps --format "{{.Names}}: {{.Status}}"');

        // Disk usage
        const disk = await execCommand("df -h / | tail -1 | awk '{print $5}'");

        // Memory
        const memory = await execCommand("free -h | grep Mem | awk '{print $3\"/\"$2}'");

        // n8n version
        let n8nVersion = 'N/A';
        try {
            n8nVersion = await execCommand('docker exec n8n n8n --version 2>/dev/null || echo "N/A"');
        } catch (e) {}

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
            // Отправляем как файл
            const logPath = `/tmp/n8n_logs_${Date.now()}.txt`;
            fs.writeFileSync(logPath, logs);
            await bot.sendDocument(chatId, logPath, {
                caption: `📋 Последние ${lines} строк логов n8n`
            });
            fs.unlinkSync(logPath);
        } else {
            await bot.sendMessage(chatId, `📋 *Логи n8n (${lines} строк):*\n\`\`\`\n${logs}\n\`\`\``, {
                parse_mode: 'Markdown'
            });
        }
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка получения логов: ${error.message}`);
    }
});

// /restart
bot.onText(/\/restart/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '🔄 Перезапускаю n8n...');

    try {
        await execCommand('docker restart n8n', 120000);

        // Ждём запуска
        await new Promise(resolve => setTimeout(resolve, 10000));

        const status = await execCommand('docker ps --filter name=n8n --format "{{.Status}}"');
        await bot.sendMessage(chatId, `✅ n8n перезапущен\nСтатус: ${status.trim()}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка перезапуска: ${error.message}`);
    }
});

// /update - ИСПРАВЛЕННАЯ КОМАНДА
bot.onText(/\/update/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;

    try {
        // Проверяем текущую и последнюю версию
        await bot.sendMessage(chatId, '🔍 Проверяю версии...');

        let currentVersion = 'unknown';
        try {
            currentVersion = (await execCommand('docker exec n8n n8n --version 2>/dev/null')).trim();
        } catch (e) {}

        let latestVersion = 'unknown';
        try {
            const response = await execCommand('curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest');
            const data = JSON.parse(response);
            latestVersion = data.tag_name?.replace('n8n@', '') || 'unknown';
        } catch (e) {}

        await bot.sendMessage(chatId, `📦 Текущая версия: ${currentVersion}\n🆕 Последняя версия: ${latestVersion}`);

        if (currentVersion === latestVersion) {
            await bot.sendMessage(chatId, '✅ У вас уже установлена последняя версия!');
            return;
        }

        // Создаём бэкап перед обновлением
        await bot.sendMessage(chatId, '💾 Создаю резервную копию перед обновлением...');
        try {
            await execCommand(`cd ${N8N_DIR} && ./backup_n8n.sh`, 300000);
            await bot.sendMessage(chatId, '✅ Бэкап создан');
        } catch (e) {
            await bot.sendMessage(chatId, '⚠️ Не удалось создать бэкап, продолжаю обновление...');
        }

        // Обновление
        await bot.sendMessage(chatId, '🔄 Обновляю n8n... Это может занять несколько минут.');

        // Пересобираем образ с новой версией
        await execCommand(`cd ${N8N_DIR} && docker compose build --no-cache n8n`, 600000);

        // Перезапускаем только n8n
        await execCommand(`cd ${N8N_DIR} && docker compose up -d n8n`, 120000);

        // Ждём запуска
        await new Promise(resolve => setTimeout(resolve, 15000));

        // Проверяем новую версию
        let newVersion = 'unknown';
        try {
            newVersion = (await execCommand('docker exec n8n n8n --version 2>/dev/null')).trim();
        } catch (e) {}

        // Очистка
        await bot.sendMessage(chatId, '🧹 Очищаю старые образы...');
        await execCommand('docker image prune -f', 60000);

        await bot.sendMessage(chatId, `✅ Обновление завершено!\n\n📦 Старая версия: ${currentVersion}\n🆕 Новая версия: ${newVersion}`);

    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка обновления: ${error.message}\n\nПопробуйте выполнить вручную:\ncd ${N8N_DIR} && ./update_n8n.sh`);
    }
});

// /backups
bot.onText(/\/backups?/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '💾 Создаю резервную копию...');

    try {
        const result = await execCommand(`cd ${N8N_DIR} && ./backup_n8n.sh 2>&1`, 300000);
        await bot.sendMessage(chatId, `✅ Бэкап создан!\n\n${result.substring(0, 1000)}`);
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка создания бэкапа: ${error.message}`);
    }
});

// Обработка ошибок
bot.on('polling_error', (error) => {
    console.error('Polling error:', error.message);
});

console.log('🤖 n8n Telegram Bot started');
console.log(`Authorized user: ${AUTHORIZED_USER}`);
BOTJS_EOF

log_success "Telegram бот создан"

# ============================================================
# Создание скриптов
# ============================================================
log_info "Создание скриптов управления..."

# update_n8n.sh - БЕЗ ограничений запуска
cat > "$INSTALL_DIR/update_n8n.sh" << 'UPDATE_EOF'
#!/bin/bash
set -e

# ============================================================
# Скрипт обновления n8n
# Может запускаться как напрямую, так и через бота
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Загрузка переменных окружения
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

LOG_FILE="./logs/update_$(date +%Y%m%d_%H%M%S).log"
mkdir -p ./logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_USER_ID}" \
            -d "text=$1" \
            -d "parse_mode=Markdown" > /dev/null 2>&1 || true
    fi
}

log "=== Начало обновления n8n ==="

# Текущая версия
CURRENT_VERSION=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
log "Текущая версия: $CURRENT_VERSION"

# Последняя версия
LATEST_VERSION=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | grep '"tag_name"' | sed -E 's/.*"n8n@([^"]+)".*/\1/' || echo "unknown")
log "Последняя версия: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    log "Уже установлена последняя версия"
    send_telegram "✅ n8n уже обновлён до последней версии $CURRENT_VERSION"
    exit 0
fi

send_telegram "🔄 Начинаю обновление n8n с $CURRENT_VERSION до $LATEST_VERSION"

# Создание бэкапа
log "Создание резервной копии..."
if [ -f ./backup_n8n.sh ]; then
    ./backup_n8n.sh || log "Предупреждение: бэкап не создан"
fi

# Остановка n8n
log "Остановка n8n..."
docker compose stop n8n

# Пересборка образа
log "Пересборка образа n8n..."
docker compose build --no-cache n8n

# Запуск n8n
log "Запуск n8n..."
docker compose up -d n8n

# Ожидание запуска
log "Ожидание запуска..."
sleep 20

# Проверка новой версии
NEW_VERSION=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
log "Новая версия: $NEW_VERSION"

# Очистка Docker
log "Очистка Docker..."
docker image prune -f > /dev/null 2>&1
docker builder prune -f > /dev/null 2>&1

# Очистка системы
log "Очистка системы..."
apt-get autoremove -y -qq > /dev/null 2>&1 || true
journalctl --vacuum-time=7d > /dev/null 2>&1 || true

# Проверка статуса
STATUS=$(docker ps --filter name=n8n --format "{{.Status}}")
log "Статус контейнера: $STATUS"

if echo "$STATUS" | grep -q "Up"; then
    log "=== Обновление успешно завершено ==="
    send_telegram "✅ n8n обновлён!

📦 Старая версия: $CURRENT_VERSION
🆕 Новая версия: $NEW_VERSION
📊 Статус: $STATUS"
else
    log "=== ОШИБКА: Контейнер не запустился ==="
    send_telegram "❌ Ошибка обновления n8n!

Контейнер не запустился.
Проверьте логи: docker logs n8n"
    exit 1
fi
UPDATE_EOF
chmod +x "$INSTALL_DIR/update_n8n.sh"

# backup_n8n.sh
cat > "$INSTALL_DIR/backup_n8n.sh" << 'BACKUP_EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Загрузка переменных окружения
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

BACKUP_DIR="./backups"
BACKUP_NAME="n8n_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_PATH"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_telegram() {
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_USER_ID}" \
            -d "text=$1" > /dev/null 2>&1 || true
    fi
}

log "=== Начало резервного копирования ==="

# Бэкап PostgreSQL
log "Создание дампа PostgreSQL..."
docker exec n8n-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_PATH/database.sql"

# Бэкап конфигурации n8n
log "Копирование конфигурации n8n..."
docker cp n8n:/home/node/.n8n "$BACKUP_PATH/n8n_data" 2>/dev/null || true

# Бэкап .env
log "Копирование .env..."
cp .env "$BACKUP_PATH/.env" 2>/dev/null || true

# Архивирование
log "Создание архива..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

# Шифрование (если есть ключ)
if [ -n "$N8N_ENCRYPTION_KEY" ]; then
    log "Шифрование архива..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${BACKUP_NAME}.tar.gz" \
        -out "${BACKUP_NAME}.tar.gz.enc" \
        -pass pass:"$N8N_ENCRYPTION_KEY"
    rm "${BACKUP_NAME}.tar.gz"
    FINAL_BACKUP="${BACKUP_NAME}.tar.gz.enc"
else
    FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
fi

# Удаление временной директории
rm -rf "$BACKUP_NAME"

# Удаление старых бэкапов (старше 7 дней)
log "Удаление старых бэкапов..."
find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" -mtime +7 -delete 2>/dev/null || true

# Размер бэкапа
BACKUP_SIZE=$(du -h "$FINAL_BACKUP" | cut -f1)

log "=== Резервное копирование завершено ==="
log "Файл: $FINAL_BACKUP"
log "Размер: $BACKUP_SIZE"

send_telegram "✅ Бэкап создан: $FINAL_BACKUP ($BACKUP_SIZE)"

echo "$BACKUP_DIR/$FINAL_BACKUP"
BACKUP_EOF
chmod +x "$INSTALL_DIR/backup_n8n.sh"

log_success "Скрипты созданы"

# ============================================================
# Создание директорий
# ============================================================
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/backups"

# ============================================================
# Запуск контейнеров
# ============================================================
log_info "Запуск Docker контейнеров..."
cd "$INSTALL_DIR" || {
    log_error "Не удалось перейти в директорию $INSTALL_DIR"
    exit 1
}

log_info "Сборка образов Docker..."
if ! docker compose build 2>&1; then
    log_error "Не удалось собрать Docker образы. Проверьте docker-compose.yml"
    exit 1
fi
log_success "Образы собраны"

log_info "Запуск контейнеров..."
if ! docker compose up -d 2>&1; then
    log_error "Не удалось запустить контейнеры. Проверьте логи: docker compose logs"
    exit 1
fi
log_success "Контейнеры запущены"

# Ожидание запуска
log_info "Ожидание запуска сервисов (до 120 секунд)..."
n8n_started=false
for i in {1..24}; do
    sleep 5
    if docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log_success "n8n запущен и отвечает на запросы!"
        n8n_started=true
        break
    fi
    echo -n "."
done
echo ""

if [[ "$n8n_started" == "false" ]]; then
    log_error "n8n не запустился в течение 120 секунд"
    log_error "Проверьте логи: docker compose logs n8n"
    log_error "Проверьте статус: docker compose ps"
    exit 1
fi

# ============================================================
# Настройка cron для бэкапов
# ============================================================
log_info "Настройка автоматических бэкапов..."
if (crontab -l 2>/dev/null | grep -v "backup_n8n.sh"; echo "0 2 * * * cd $INSTALL_DIR && ./backup_n8n.sh >> ./logs/backup.log 2>&1") | crontab - 2>&1; then
    log_success "Автоматические бэкапы настроены (ежедневно в 2:00)"
else
    log_warning "Не удалось настроить автоматические бэкапы через cron"
    log_warning "Вы можете настроить их вручную позже"
fi

# ============================================================
# Финальная проверка
# ============================================================
echo ""
echo "=============================================="
echo "           Установка завершена!"
echo "=============================================="
echo ""

docker compose ps

echo ""
log_success "╔════════════════════════════════════════════════════════╗"
log_success "║          n8n установлен и готов к работе!              ║"
log_success "╚════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Веб-интерфейсы:"
echo "   • n8n:            https://${DOMAIN}"
echo "   • pgAdmin:        https://${PGADMIN_DOMAIN}"
echo "     Логин:          ${EMAIL}"
echo "     Пароль:         ${PGADMIN_PASSWORD}"
echo ""
echo "   • Redis Commander: https://${REDIS_DOMAIN}"
echo "     Логин:          admin"
echo "     Пароль:         ${REDIS_UI_PASSWORD}"
echo ""
echo "🤖 Telegram бот запущен и готов к работе"
echo ""
echo "📝 Полезные команды:"
echo "   cd $INSTALL_DIR"
echo "   docker compose ps          # Статус контейнеров"
echo "   docker compose logs -f n8n # Логи n8n"
echo "   ./update_n8n.sh            # Обновить n8n"
echo "   ./backup_n8n.sh            # Создать бэкап"
echo "   ./restore_n8n.sh <файл>    # Восстановить из бэкапа"
echo ""

# Отправка уведомления в Telegram
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
    log_info "Отправка уведомления в Telegram..."
    N8N_VERSION=$(docker exec n8n n8n --version 2>/dev/null || echo "N/A")

    if curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=✅ *n8n v3+ успешно установлен!*

🌐 *Веб-интерфейсы:*
• n8n: https://${DOMAIN}
• pgAdmin: https://${PGADMIN_DOMAIN}
• Redis: https://${REDIS_DOMAIN}

📦 Версия n8n: ${N8N_VERSION}

🔐 *Пароли сохранены в .env файле*

Используйте /start для просмотра команд бота." \
        -d "parse_mode=Markdown" > /dev/null 2>&1; then
        log_success "Уведомление отправлено в Telegram"
    else
        log_warning "Не удалось отправить уведомление в Telegram. Проверьте TG_BOT_TOKEN и TG_USER_ID"
    fi
else
    log_info "Telegram бот не настроен (пропущено уведомление)"
fi

log_success "Готово!"
