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
read -p "Email для SSL сертификата: " EMAIL
read -sp "Пароль PostgreSQL: " DB_PASSWORD
echo ""
read -p "Telegram Bot Token: " TG_BOT_TOKEN
read -p "Telegram User ID (ваш ID): " TG_USER_ID

# Генерация ключа шифрования
ENCRYPTION_KEY=$(openssl rand -hex 32)
log_info "Сгенерирован ключ шифрования"

# Директория установки
INSTALL_DIR="/opt/n8n"
REPO_URL="https://github.com/kalibrrbilak/n8n-install.git"

log_info "Обновление системы..."
apt-get update -qq
apt-get upgrade -y -qq

log_info "Установка зависимостей..."
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq

# ============================================================
# Установка Docker Engine v29
# ============================================================
log_info "Установка Docker Engine..."

# Удаление старых версий
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y -qq $pkg 2>/dev/null || true
done

# Добавление репозитория Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq

# Установка Docker (последняя версия v29)
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Проверка Docker
if ! docker --version; then
    log_error "Docker не установлен"
    exit 1
fi
log_success "Docker установлен: $(docker --version)"

# Запуск Docker
systemctl enable docker
systemctl start docker

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
# n8n Configuration
DOMAIN=${DOMAIN}
N8N_HOST=${DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${DOMAIN}/
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Database
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n
POSTGRES_NON_ROOT_USER=n8n
POSTGRES_NON_ROOT_PASSWORD=${DB_PASSWORD}

# Redis
REDIS_HOST=n8n-redis
REDIS_PORT=6379

# Queue mode для производительности
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=n8n-redis
QUEUE_BULL_REDIS_PORT=6379

# SSL
SSL_EMAIL=${EMAIL}

# Telegram Bot
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_USER_ID=${TG_USER_ID}

# Timezone
GENERIC_TIMEZONE=Europe/Moscow
TZ=Europe/Moscow

# n8n settings
N8N_METRICS=true
N8N_LOG_LEVEL=info
N8N_DIAGNOSTICS_ENABLED=false
N8N_PERSONALIZATION_ENABLED=false
EOF

chmod 600 "$INSTALL_DIR/.env"
log_success "Конфигурация создана"

# ============================================================
# Создание docker-compose.yml
# ============================================================
log_info "Создание docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" << 'COMPOSE_EOF'
services:
  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - EXECUTIONS_MODE=${EXECUTIONS_MODE}
      - QUEUE_BULL_REDIS_HOST=${QUEUE_BULL_REDIS_HOST}
      - QUEUE_BULL_REDIS_PORT=${QUEUE_BULL_REDIS_PORT}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${TZ}
      - N8N_METRICS=${N8N_METRICS}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - N8N_DIAGNOSTICS_ENABLED=${N8N_DIAGNOSTICS_ENABLED}
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

  n8n-postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
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

  n8n-redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

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
      - "--certificatesresolvers.letsencrypt.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
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

  n8n-bot:
    build:
      context: ./bot
      dockerfile: Dockerfile
    container_name: n8n-bot
    restart: unless-stopped
    environment:
      - TG_BOT_TOKEN=${TG_BOT_TOKEN}
      - TG_USER_ID=${TG_USER_ID}
      - N8N_DIR=/opt/n8n
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/n8n:/opt/n8n:ro
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
  postgres_data:
  redis_data:
  traefik_certs:
COMPOSE_EOF

log_success "docker-compose.yml создан"

# ============================================================
# Создание Dockerfile.n8n
# ============================================================
log_info "Создание Dockerfile.n8n..."
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
    git

# Puppeteer конфигурация
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV CHROME_PATH=/usr/bin/chromium-browser

# n8n конфигурация
ENV N8N_USER_FOLDER=/home/node/.n8n

USER node

WORKDIR /home/node

EXPOSE 5678

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --spider -q http://localhost:5678/healthz || exit 1

CMD ["n8n"]
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
cd "$INSTALL_DIR"
docker compose build
docker compose up -d

# Ожидание запуска
log_info "Ожидание запуска сервисов (до 120 секунд)..."
for i in {1..24}; do
    sleep 5
    if docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        log_success "n8n запущен!"
        break
    fi
    echo -n "."
done
echo ""

# ============================================================
# Настройка cron для бэкапов
# ============================================================
log_info "Настройка автоматических бэкапов..."
(crontab -l 2>/dev/null | grep -v "backup_n8n.sh"; echo "0 2 * * * cd $INSTALL_DIR && ./backup_n8n.sh >> ./logs/backup.log 2>&1") | crontab -

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
log_success "n8n доступен по адресу: https://${DOMAIN}"
log_success "Telegram бот запущен и готов к работе"
echo ""
echo "Полезные команды:"
echo "  cd $INSTALL_DIR"
echo "  docker compose ps          # Статус контейнеров"
echo "  docker compose logs -f n8n # Логи n8n"
echo "  ./update_n8n.sh            # Обновить n8n"
echo "  ./backup_n8n.sh            # Создать бэкап"
echo ""

# Отправка уведомления в Telegram
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
    N8N_VERSION=$(docker exec n8n n8n --version 2>/dev/null || echo "N/A")
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=✅ n8n успешно установлен!

🌐 URL: https://${DOMAIN}
📦 Версия: ${N8N_VERSION}

Используйте /start для просмотра команд бота." \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true
fi

log_success "Готово!"
