# n8n Auto Install v2.0

Автоматическая установка **n8n 2.0+** на Ubuntu 22.04 LTS с полной поддержкой Docker, AI, Proxy и Telegram-управлением.

## Быстрая установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kalibrrbilak/n8n-install/main/install.sh)
```

## Возможности v2.0

| Функция | Описание |
|---------|----------|
| **n8n 2.0+** | Последняя версия с поддержкой Execute Command |
| **PostgreSQL 16** | Производительная база данных |
| **Redis 7** | Queue mode для масштабирования |
| **Traefik v3** | Reverse proxy с автоматическим SSL |
| **Proxy** | Поддержка HTTP/HTTPS прокси |
| **Gemini AI** | Интеграция с Google Gemini через CLI |
| **Telegram Bot** | Управление сервером через бота |
| **Auto Backup** | Ежедневные зашифрованные бэкапы |

## Требования

- **ОС**: Ubuntu 22.04 / 24.04 LTS (чистый сервер)
- **RAM**: минимум 2GB (рекомендуется 4GB)
- **Диск**: минимум 20GB свободного места
- **Домен**: настроенная A-запись на IP сервера
- **Telegram Bot**: токен от [@BotFather](https://t.me/BotFather) (опционально)

## Интерактивная установка

Скрипт запросит следующие данные:

1. **Прокси** (опционально) - формат: `http://login:password@ip:port`
2. **Gemini API Key** (опционально) - получить на [aistudio.google.com](https://aistudio.google.com/app/apikey)
3. **Домен** - например, `n8n.example.com`
4. **Email** - для SSL сертификата Let's Encrypt
5. **Пароль PostgreSQL** - или автогенерация
6. **Telegram Bot Token** (опционально)
7. **Telegram User ID** (опционально)

## Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │   Traefik   │ :80/:443 (SSL)
                    │    v3.2     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌────▼────┐ ┌─────▼─────┐
        │    n8n    │ │ Postgres │ │   Redis   │
        │   2.0+    │ │    16    │ │     7     │
        └─────┬─────┘ └──────────┘ └───────────┘
              │
        ┌─────▼─────┐
        │  Gemini   │ (Execute Command)
        │    CLI    │
        └───────────┘
```

## Структура проекта

```
/opt/main/                  # Основная директория
├── .env                    # Конфигурация (секреты)
├── docker-compose.yml      # Docker конфигурация
├── Dockerfile.n8n          # Кастомный образ n8n
├── install.sh              # Скрипт установки
├── update_n8n.sh           # Скрипт обновления
├── backup_n8n.sh           # Скрипт бэкапа
├── logs/                   # Логи
├── backups/                # Бэкапы
└── bot/                    # Telegram бот
    ├── bot.js
    ├── package.json
    └── Dockerfile

/opt/n8n_custom/            # Кастомные файлы (права 1000:1000)
/opt/gemini/                # Gemini CLI
```

## Команды управления

### Терминал

```bash
cd /opt/main

# Статус контейнеров
docker compose ps

# Логи n8n
docker compose logs -f n8n

# Перезапуск n8n
docker compose restart n8n

# Обновление n8n
n8n-update                  # или ./update_n8n.sh

# Создать бэкап
./backup_n8n.sh

# Запустить с Telegram ботом
docker compose --profile bot up -d
```

### Telegram бот

| Команда | Описание |
|---------|----------|
| `/start` | Справка по командам |
| `/status` | Статус сервера и контейнеров |
| `/logs [N]` | Последние N строк логов |
| `/update` | Обновить n8n до последней версии |
| `/backup` | Создать резервную копию |
| `/restart` | Перезапустить n8n |
| `/cleanup` | Очистить неиспользуемые Docker ресурсы |

## Gemini AI в n8n

После установки Gemini CLI доступен в n8n через ноду **Execute Command**:

```bash
# Прямой вызов
gemini-cli "Напиши функцию для сортировки массива на JavaScript"

# В n8n Execute Command
/opt/gemini/gemini-cli "Ваш промпт"
```

## Proxy

При указании прокси скрипт автоматически настроит:

- Системный прокси (`/etc/environment`)
- APT прокси (`/etc/apt/apt.conf.d/95proxy`)
- Docker daemon прокси
- n8n переменные (`GLOBAL_HTTP_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY`)

## Безопасность

- **N8N_ENCRYPTION_KEY** - уникальный 64-символьный ключ
- **Execute Command** - включен через `N8N_ALLOW_EXEC=true`
- **Бэкапы** - шифруются ключом шифрования n8n
- **Telegram бот** - доступ только авторизованному пользователю
- **Docker socket** - read-only доступ для бота

## Переменные окружения

Основные переменные в `.env`:

```env
# Обязательные
DOMAIN=n8n.example.com
N8N_ENCRYPTION_KEY=...
POSTGRES_PASSWORD=...
SSL_EMAIL=...

# Опциональные
HTTP_PROXY=http://user:pass@ip:port
GEMINI_API_KEY=...
TG_BOT_TOKEN=...
TG_USER_ID=...
```

## Обновление

### Автоматическое (через бота)

Отправьте `/update` в Telegram боту.

### Ручное

```bash
cd /opt/main
./update_n8n.sh
```

Или глобально:

```bash
n8n-update
```

## Бэкапы

### Автоматические

Ежедневно в 03:00 (cron). Хранятся 7 дней.

### Ручные

```bash
cd /opt/main
./backup_n8n.sh
```

Бэкапы сохраняются в `/opt/main/backups/` и шифруются ключом `N8N_ENCRYPTION_KEY`.

### Восстановление

```bash
cd /opt/main/backups

# Расшифровка
openssl enc -aes-256-cbc -d -pbkdf2 \
  -in n8n_backup_XXXXXX.tar.gz.enc \
  -out backup.tar.gz \
  -pass pass:"ваш_N8N_ENCRYPTION_KEY"

# Распаковка
tar -xzf backup.tar.gz
```

## Устранение проблем

### n8n не запускается

```bash
docker compose logs n8n
docker compose ps
```

### SSL сертификат не получен

1. Проверьте DNS: `nslookup ваш-домен`
2. Убедитесь что порты 80/443 открыты
3. Проверьте логи Traefik: `docker compose logs n8n-traefik`

### Telegram бот не отвечает

1. Проверьте токен и User ID в `.env`
2. Убедитесь что бот запущен: `docker compose --profile bot ps`
3. Логи бота: `docker compose logs n8n-bot`

## Изменения v2.0

- Полная поддержка n8n 2.0+ с миграциями БД
- Интерактивный пошаговый установщик
- Поддержка HTTP/HTTPS прокси
- Интеграция Gemini AI CLI
- Execute Command node включен по умолчанию
- Кастомная папка `/opt/n8n_custom` с правами 1000:1000
- Глобальный скрипт обновления `/usr/local/bin/n8n-update`
- Улучшенный Telegram бот с командой `/cleanup`
- Healthcheck для всех контейнеров
- Resource limits для Docker контейнеров
- Логирование установки в файл

## Лицензия

MIT

## Благодарности

Основано на [n8n-beget-install](https://github.com/kalininlive/n8n-beget-install)
