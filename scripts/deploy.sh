#!/bin/bash
# olcRTC Universal Installer (Hardened Version)
# Usage: curl -sSL https://raw.githubusercontent.com/domadomlab/olcrtc-vps-manager/main/scripts/deploy.sh | bash

BLUE='\033[0-34m'
YELLOW='\033[1-33m'
GREEN='\033[0-32m'
RED='\033[0-31m'
NC='\033[0m'

echo -e "${BLUE}--- 🚀 olcRTC Universal Deployment Wizard ---${NC}"

# 1. More robust mode selection with timeout
echo -e "Выберите режим установки:"
echo -e "${GREEN}1)${NC} Локальная установка на ЭТОМ сервере (VPS)"
echo -e "${GREEN}2)${NC} Удаленный деплой со своего ПК на VPS (через SSH)"
echo -e "${YELLOW}(Автоматический выбор режима 1 через 5 секунд...)${NC}"

# Attempt to read mode from TTY with timeout
MODE=""
if [ -t 0 ]; then
    read -t 5 -p "Ваш выбор [1/2]: " MODE
else
    read -t 5 -p "Ваш выбор [1/2]: " MODE < /dev/tty
fi

MODE=${MODE:-1}

if [[ "$MODE" == "1" ]]; then
    echo -e "\n${GREEN}>>> ВЫБРАН РЕЖИМ ЛОКАЛЬНОЙ УСТАНОВКИ <<<${NC}"
    curl -sSL -H "Cache-Control: no-cache" https://raw.githubusercontent.com/domadomlab/olcrtc-vps-manager/main/scripts/vps-install.sh > vps-install.sh
    bash vps-install.sh
    rm vps-install.sh
    exit 0
fi

# --- REMOTE INSTALLATION ---
echo -e "\n${BLUE}>>> ВЫБРАН РЕЖИМ УДАЛЕННОГО ДЕПЛОЯ <<<${NC}"

read -p "Введите IP адрес VPS: " VPS_IP < /dev/tty
read -p "Введите пароль root: " PASS < /dev/tty
read -p "Введите Room ID Телемоста: " ROOM_ID < /dev/tty
read -p "Введите Telegram Bot Token (опционально): " BOT_TOKEN < /dev/tty

if [[ -z "$VPS_IP" || -z "$PASS" || -z "$ROOM_ID" ]]; then
    echo -e "${RED}Ошибка: IP, Пароль и Room ID обязательны.${NC}"
    exit 1
fi

# Check for sshpass locally
if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}Установка sshpass...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}Пожалуйста, установите sshpass вручную.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}Соединяюсь с $VPS_IP и запускаю установку...${NC}"
REMOTE_CMD="curl -sSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/domadomlab/olcrtc-vps-manager/main/scripts/vps-install.sh > vps-install.sh && bash vps-install.sh '$ROOM_ID' '$BOT_TOKEN'; rm vps-install.sh"
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -tt root@"$VPS_IP" "$REMOTE_CMD"

echo -e "\n${GREEN}Деплой на удаленный сервер завершен.${NC}"
