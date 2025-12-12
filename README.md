# n8n Auto Install

Автоматическая установка n8n с PostgreSQL, Redis, Traefik и Telegram-ботом для управления.

## Возможности

- Установка n8n 2.0+ в один клик
- PostgreSQL 16 + Redis 7 для производительности
- Автоматический SSL через Traefik + Let's Encrypt
- Telegram-бот для управления (статус, логи, обновление, бэкапы)
- Автоматические зашифрованные бэкапы ежедневно
- Docker Engine v29 (актуальная версия)

## Требования

- Ubuntu 22.04 / 24.04 (чистый сервер)
- Минимум 2GB RAM, 20GB диск
- Домен, направленный на сервер
- Telegram бот (получить у [@BotFather](https://t.me/BotFather))

## Быстрая установка

```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_USERNAME/n8n-install/main/install.sh)
```

## Что устанавливается

| Компонент | Описание |
|-----------|----------|
| n8n | Платформа автоматизации (latest) |
| PostgreSQL 16 | База данных |
| Redis 7 | Кэш и очереди |
| Traefik | Reverse proxy + SSL |
| Telegram Bot | Управление сервером |

## Команды бота

| Команда | Описание |
|---------|----------|
| `/start` | Справка по командам |
| `/status` | Статус сервера и контейнеров |
| `/logs` | Последние логи n8n |
| `/update` | Обновить n8n до последней версии |
| `/backups` | Создать резервную копию |
| `/restart` | Перезапустить n8n |

## Структура проекта

```
n8n-install/
├── install.sh          # Скрипт установки
├── docker-compose.yml  # Конфигурация контейнеров
├── Dockerfile.n8n      # Кастомный образ n8n
├── update_n8n.sh       # Скрипт обновления
├── backup_n8n.sh       # Скрипт бэкапа
├── .env.example        # Пример конфигурации
└── bot/
    ├── bot.js          # Telegram бот
    └── package.json    # Зависимости бота
```

## Ручное управление

```bash
# Перейти в директорию
cd /opt/n8n

# Статус контейнеров
docker compose ps

# Логи n8n
docker compose logs -f n8n

# Перезапуск
docker compose restart n8n

# Обновление
./update_n8n.sh

# Бэкап
./backup_n8n.sh
```

## Изменения относительно оригинала

- Docker Engine обновлён до v29 (было v28.1.1)
- Поддержка n8n 2.0 с новыми breaking changes
- Исправлена проблема запуска обновления через бота
- PostgreSQL обновлён до версии 16
- Добавлена команда `/restart` в бота
- Улучшена обработка ошибок
- Добавлен healthcheck для всех сервисов

## Лицензия

MIT

## Благодарности

Основано на [n8n-beget-install](https://github.com/kalininlive/n8n-beget-install)
