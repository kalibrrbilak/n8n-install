FROM node:20-alpine

# Установка Docker CLI для управления контейнерами
RUN apk add --no-cache docker-cli bash curl

WORKDIR /app

# Копирование зависимостей
COPY package.json ./
RUN npm install --production

# Копирование кода бота
COPY bot.js ./

# Запуск бота
CMD ["node", "bot.js"]
