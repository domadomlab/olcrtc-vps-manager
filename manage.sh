#!/bin/bash
# Интерактивное управление olcRTC
# Позволяет менять комнату, генерировать QR и следить за статусом

ENV_FILE=".env"
SCRIPTS_DIR="scripts"

# Цвета для вывода
GREEN='\033[0-32m'
BLUE='\033[0-34m'
YELLOW='\033[1-33m'
NC='\033[0m'

# Загрузка текущих настроек
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo -e "${YELLOW}Файл .env не найден. Создаю стандартный...${NC}"
    exit 1
fi

show_menu() {
    clear
    echo -e "${BLUE}=== Управление olcRTC Туннелем ===${NC}"
    echo -e "Текущая комната: ${GREEN}$OLCRTC_ROOM_ID${NC}"
    echo -e "VPS IP:          ${GREEN}$OLCRTC_VPS_IP${NC}"
    echo "---------------------------------"
    echo "1. Показать URI и QR-код для клиента"
    echo "2. Сменить Room ID (ID комнаты Телемоста)"
    echo "3. Перезапустить туннель на сервере (Apply changes)"
    echo "4. Показать логи сервера (Real-time)"
    echo "5. Выход"
    echo "---------------------------------"
}

generate_uri() {
    URI="olcrtc://${OLCRTC_CARRIER}?${OLCRTC_TRANSPORT}<vp8-fps=${OLCRTC_VP8_FPS}&vp8-batch=${OLCRTC_VP8_BATCH}>@${OLCRTC_ROOM_ID}#${OLCRTC_KEY}%${OLCRTC_CLIENT_ID}\$STABLE_VPS"
    echo "$URI"
}

while true; do
    show_menu
    read -p "Выберите действие [1-5]: " choice

    case $choice in
        1)
            echo -e "\n${BLUE}URI для импорта в приложение:${NC}"
            URI=$(generate_uri)
            echo -e "${YELLOW}$URI${NC}\n"
            echo -e "${BLUE}QR-код для сканирования (генерируется на сервере):${NC}"
            # Генерируем QR на сервере и выводим в консоль
            sshpass -p "$OLCRTC_PASS" ssh -o StrictHostKeyChecking=no root@"$OLCRTC_VPS_IP" "qrencode -t ansiutf8 '$URI'"
            read -p "Нажмите Enter, чтобы вернуться в меню..."
            ;;
        2)
            read -p "Введите новый Room ID: " new_room
            if [[ -n "$new_room" ]]; then
                # Обновляем в .env локально
                sed -i "s/OLCRTC_ROOM_ID=.*/OLCRTC_ROOM_ID=$new_room/" "$ENV_FILE"
                echo -e "${GREEN}Room ID обновлен локально.${NC}"
                echo -e "${YELLOW}Не забудьте применить изменения (пункт 3)!${NC}"
            fi
            sleep 2
            ;;
        3)
            echo -e "${BLUE}Отправляю конфигурацию на сервер и перезапускаю...${NC}"
            ./scripts/deploy.sh
            read -p "Готово. Нажмите Enter..."
            ;;
        4)
            ./scripts/monitor.sh
            ;;
        5)
            echo "Выход..."
            exit 0
            ;;
        *)
            echo "Неверный выбор."
            sleep 1
            ;;
    esac
done
