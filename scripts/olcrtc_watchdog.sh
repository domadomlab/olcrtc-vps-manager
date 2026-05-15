#!/bin/bash

CONTAINER_NAME="olcrtc-server"
LOG_FILE="/root/watchdog.log"

# Функция для логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# 1. Проверка, запущен ли контейнер вообще
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    log "Контейнер $CONTAINER_NAME не найден! Пытаюсь запустить..."
    docker start $CONTAINER_NAME
fi

# 2. Проверка последних логов на ошибки связи
# Если в последних 20 строках есть ошибка 'ConferenceNotFound' или 'timeout'
RECENT_LOGS=$(docker logs --tail 20 $CONTAINER_NAME 2>&1)

if echo "$RECENT_LOGS" | grep -qE "ConferenceNotFound|datachannel timeout|failed to connect"; then
    log "Обнаружена критическая ошибка в логах. Перезапускаю туннель..."
    docker restart $CONTAINER_NAME
fi

# Ограничение размера лога вотчдога (не более 1000 строк)
tail -n 1000 $LOG_FILE > ${LOG_FILE}.tmp && mv ${LOG_FILE}.tmp $LOG_FILE
