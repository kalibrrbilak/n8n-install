/**
 * n8n Telegram Management Bot
 * Версия 2.0 - исправлена проблема с командой /update
 */

const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

// Конфигурация
const BOT_TOKEN = process.env.TG_BOT_TOKEN;
const AUTHORIZED_USER = process.env.TG_USER_ID;
const N8N_DIR = process.env.N8N_DIR || '/opt/main';

// Проверка обязательных переменных
if (!BOT_TOKEN || !AUTHORIZED_USER) {
    console.error('ERROR: Missing required environment variables');
    console.error('Required: TG_BOT_TOKEN, TG_USER_ID');
    process.exit(1);
}

// Инициализация бота
const bot = new TelegramBot(BOT_TOKEN, { polling: true });

/**
 * Проверка авторизации пользователя
 */
const isAuthorized = (msg) => {
    const userId = String(msg.from.id);
    const authorized = userId === String(AUTHORIZED_USER);
    if (!authorized) {
        console.log(`Unauthorized access attempt from user ${userId}`);
    }
    return authorized;
};

/**
 * Выполнение команды с таймаутом
 */
const execCommand = (cmd, timeout = 60000) => {
    return new Promise((resolve, reject) => {
        const options = {
            timeout: timeout,
            maxBuffer: 1024 * 1024 * 10, // 10MB
            cwd: N8N_DIR
        };

        exec(cmd, options, (error, stdout, stderr) => {
            if (error) {
                // Если это таймаут, возвращаем специальное сообщение
                if (error.killed) {
                    reject(new Error('Command timed out'));
                } else {
                    reject(new Error(stderr || error.message));
                }
            } else {
                resolve(stdout || stderr || 'OK');
            }
        });
    });
};

/**
 * Отправка длинного сообщения (разбивка на части)
 */
const sendLongMessage = async (chatId, text, options = {}) => {
    const maxLength = 4000;
    if (text.length <= maxLength) {
        return bot.sendMessage(chatId, text, options);
    }

    const parts = [];
    for (let i = 0; i < text.length; i += maxLength) {
        parts.push(text.substring(i, i + maxLength));
    }

    for (let i = 0; i < parts.length; i++) {
        await bot.sendMessage(chatId, parts[i], i === 0 ? options : {});
        // Небольшая задержка между сообщениями
        await new Promise(resolve => setTimeout(resolve, 100));
    }
};

// ============================================================
// Команды бота
// ============================================================

/**
 * /start и /help - Справка
 */
bot.onText(/\/(start|help)/, (msg) => {
    if (!isAuthorized(msg)) return;

    const helpText = `
*n8n Management Bot v2.0*

Доступные команды:

/status - Статус сервера и контейнеров
/logs [N] - Последние N строк логов (по умолчанию 50)
/update - Обновить n8n до последней версии
/backup - Создать резервную копию
/restart - Перезапустить n8n
/disk - Информация о дисковом пространстве
/help - Показать эту справку

_Бот управляет n8n через Docker_
    `;
    bot.sendMessage(msg.chat.id, helpText, { parse_mode: 'Markdown' });
});

/**
 * /status - Статус системы
 */
bot.onText(/\/status/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    const statusMsg = await bot.sendMessage(chatId, '⏳ Получаю статус системы...');

    try {
        // Собираем информацию параллельно
        const [uptime, containers, disk, memory, n8nVersion] = await Promise.all([
            execCommand('uptime -p').catch(() => 'N/A'),
            execCommand('docker ps --format "{{.Names}}: {{.Status}}"').catch(() => 'N/A'),
            execCommand("df -h / | tail -1 | awk '{print $5\" used of \"$2}'").catch(() => 'N/A'),
            execCommand("free -h | grep Mem | awk '{print $3\" / \"$2}'").catch(() => 'N/A'),
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

        await bot.editMessageText(statusText, {
            chat_id: chatId,
            message_id: statusMsg.message_id,
            parse_mode: 'Markdown'
        });
    } catch (error) {
        await bot.editMessageText(`❌ Ошибка: ${error.message}`, {
            chat_id: chatId,
            message_id: statusMsg.message_id
        });
    }
});

/**
 * /logs - Логи n8n
 */
bot.onText(/\/logs(?:\s+(\d+))?/, async (msg, match) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    const lines = parseInt(match[1]) || 50;

    await bot.sendMessage(chatId, `⏳ Получаю последние ${lines} строк логов...`);

    try {
        const logs = await execCommand(`docker logs n8n --tail ${lines} 2>&1`, 30000);

        if (!logs || logs.trim().length === 0) {
            await bot.sendMessage(chatId, '📋 Логи пусты');
            return;
        }

        if (logs.length > 3900) {
            // Отправляем как файл
            const logPath = `/tmp/n8n_logs_${Date.now()}.txt`;
            fs.writeFileSync(logPath, logs);
            await bot.sendDocument(chatId, logPath, {
                caption: `📋 Последние ${lines} строк логов n8n`
            });
            fs.unlinkSync(logPath);
        } else {
            await bot.sendMessage(chatId, `📋 *Логи n8n:*\n\`\`\`\n${logs.substring(0, 3800)}\n\`\`\``, {
                parse_mode: 'Markdown'
            });
        }
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка получения логов: ${error.message}`);
    }
});

/**
 * /restart - Перезапуск n8n
 */
bot.onText(/\/restart/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '🔄 Перезапускаю n8n...');

    try {
        await execCommand('docker restart n8n', 120000);

        // Ждём запуска
        await new Promise(resolve => setTimeout(resolve, 15000));

        // Проверяем статус
        const status = await execCommand('docker ps --filter name=n8n --format "{{.Status}}"');

        if (status.includes('Up')) {
            await bot.sendMessage(chatId, `✅ n8n успешно перезапущен\n📊 Статус: ${status.trim()}`);
        } else {
            await bot.sendMessage(chatId, `⚠️ n8n перезапущен, но статус: ${status.trim()}\n\nПроверьте логи: /logs`);
        }
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка перезапуска: ${error.message}`);
    }
});

/**
 * /update - Обновление n8n (ИСПРАВЛЕННАЯ ВЕРСИЯ)
 *
 * Основная проблема в оригинале: скрипт update_n8n.sh имел защиту от запуска
 * не через бота, но бот вызывал его некорректно.
 *
 * Решение: команда обновления теперь выполняется напрямую через Docker команды
 */
bot.onText(/\/update/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;

    try {
        // Шаг 1: Проверка версий
        await bot.sendMessage(chatId, '🔍 Проверяю версии n8n...');

        let currentVersion = 'unknown';
        try {
            currentVersion = (await execCommand('docker exec n8n n8n --version 2>/dev/null')).trim();
        } catch (e) {
            console.log('Could not get current version:', e.message);
        }

        let latestVersion = 'unknown';
        try {
            const response = await execCommand('curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest');
            const data = JSON.parse(response);
            latestVersion = data.tag_name?.replace('n8n@', '').replace('v', '') || 'unknown';
        } catch (e) {
            console.log('Could not get latest version:', e.message);
        }

        await bot.sendMessage(chatId,
            `📦 Текущая версия: *${currentVersion}*\n🆕 Последняя версия: *${latestVersion}*`,
            { parse_mode: 'Markdown' }
        );

        // Проверка необходимости обновления
        if (currentVersion !== 'unknown' && currentVersion === latestVersion) {
            await bot.sendMessage(chatId, '✅ У вас уже установлена последняя версия!');
            return;
        }

        // Шаг 2: Создание бэкапа
        await bot.sendMessage(chatId, '💾 Создаю резервную копию перед обновлением...');
        try {
            await execCommand(`${N8N_DIR}/backup_n8n.sh`, 300000);
            await bot.sendMessage(chatId, '✅ Бэкап создан');
        } catch (e) {
            await bot.sendMessage(chatId, '⚠️ Не удалось создать бэкап, но продолжаю обновление...');
            console.log('Backup error:', e.message);
        }

        // Шаг 3: Остановка n8n
        await bot.sendMessage(chatId, '⏹ Останавливаю n8n...');
        await execCommand(`cd ${N8N_DIR} && docker compose stop n8n`, 60000);

        // Шаг 4: Пересборка образа
        await bot.sendMessage(chatId, '🔨 Пересобираю образ n8n (это может занять 5-10 минут)...');
        await execCommand(`cd ${N8N_DIR} && docker compose build --no-cache n8n`, 600000);

        // Шаг 5: Запуск
        await bot.sendMessage(chatId, '🚀 Запускаю обновлённый n8n...');
        await execCommand(`cd ${N8N_DIR} && docker compose up -d n8n`, 120000);

        // Шаг 6: Ожидание запуска
        await bot.sendMessage(chatId, '⏳ Ожидаю запуска сервиса...');
        await new Promise(resolve => setTimeout(resolve, 20000));

        // Шаг 7: Проверка новой версии
        let newVersion = 'unknown';
        try {
            newVersion = (await execCommand('docker exec n8n n8n --version 2>/dev/null')).trim();
        } catch (e) {
            console.log('Could not get new version:', e.message);
        }

        // Шаг 8: Очистка
        await bot.sendMessage(chatId, '🧹 Очищаю старые образы...');
        await execCommand('docker image prune -f', 60000).catch(() => {});

        // Шаг 9: Проверка статуса
        const status = await execCommand('docker ps --filter name=n8n --format "{{.Status}}"').catch(() => 'unknown');

        if (status.includes('Up')) {
            await bot.sendMessage(chatId,
                `✅ *Обновление завершено успешно!*\n\n` +
                `📦 Старая версия: ${currentVersion}\n` +
                `🆕 Новая версия: ${newVersion}\n` +
                `📊 Статус: ${status.trim()}`,
                { parse_mode: 'Markdown' }
            );
        } else {
            await bot.sendMessage(chatId,
                `⚠️ *Обновление завершено с предупреждением*\n\n` +
                `Контейнер может быть ещё в процессе запуска.\n` +
                `Статус: ${status.trim()}\n\n` +
                `Проверьте через минуту: /status`,
                { parse_mode: 'Markdown' }
            );
        }

    } catch (error) {
        console.error('Update error:', error);
        await bot.sendMessage(chatId,
            `❌ *Ошибка обновления*\n\n` +
            `${error.message}\n\n` +
            `Попробуйте выполнить вручную:\n` +
            `\`cd ${N8N_DIR} && ./update_n8n.sh\``,
            { parse_mode: 'Markdown' }
        );
    }
});

/**
 * /backup - Создание бэкапа
 */
bot.onText(/\/backup/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;
    await bot.sendMessage(chatId, '💾 Создаю резервную копию...');

    try {
        const result = await execCommand(`${N8N_DIR}/backup_n8n.sh 2>&1`, 300000);

        // Получаем информацию о последнем бэкапе
        const backupInfo = await execCommand(`ls -lh ${N8N_DIR}/backups/*.tar.gz* 2>/dev/null | tail -1`).catch(() => '');

        await bot.sendMessage(chatId,
            `✅ *Бэкап создан успешно!*\n\n` +
            `📁 ${backupInfo.trim() || 'Файл создан'}`,
            { parse_mode: 'Markdown' }
        );
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка создания бэкапа: ${error.message}`);
    }
});

/**
 * /disk - Информация о диске
 */
bot.onText(/\/disk/, async (msg) => {
    if (!isAuthorized(msg)) return;

    const chatId = msg.chat.id;

    try {
        const [diskUsage, dockerUsage] = await Promise.all([
            execCommand('df -h /'),
            execCommand('docker system df').catch(() => 'N/A')
        ]);

        const text = `
💾 *Дисковое пространство*

*Система:*
\`\`\`
${diskUsage.trim()}
\`\`\`

*Docker:*
\`\`\`
${dockerUsage.trim()}
\`\`\`
        `;

        await bot.sendMessage(chatId, text, { parse_mode: 'Markdown' });
    } catch (error) {
        await bot.sendMessage(chatId, `❌ Ошибка: ${error.message}`);
    }
});

// ============================================================
// Обработка ошибок
// ============================================================

bot.on('polling_error', (error) => {
    console.error('Polling error:', error.code, error.message);
});

bot.on('error', (error) => {
    console.error('Bot error:', error.message);
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('Shutting down bot...');
    bot.stopPolling();
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('Shutting down bot...');
    bot.stopPolling();
    process.exit(0);
});

// ============================================================
// Запуск
// ============================================================

console.log('========================================');
console.log('  n8n Telegram Management Bot v2.0');
console.log('========================================');
console.log(`Authorized user ID: ${AUTHORIZED_USER}`);
console.log(`n8n directory: ${N8N_DIR}`);
console.log('Bot started and waiting for commands...');
