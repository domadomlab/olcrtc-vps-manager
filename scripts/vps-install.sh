#!/bin/bash
# olcRTC Direct VPS Installer
# Usage: curl -sSL https://raw.githubusercontent.com/domadomlab/olcrtc-vps-manager/main/scripts/vps-install.sh | bash

BLUE='\033[0-34m'
YELLOW='\033[1-33m'
GREEN='\033[0-32m'
RED='\033[0-31m'
NC='\033[0m'

echo -e "${BLUE}--- 🚀 olcRTC Direct VPS Deployment ---${NC}"

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Пожалуйста, запустите скрипт от имени root (sudo).${NC}"
  exit 1
fi

# 2. Collect inputs (from argument or interactively)
ROOM_ID=$1
BOT_TOKEN=$2

if [[ -z "$ROOM_ID" ]]; then
    while [[ -z "$ROOM_ID" ]]; do
        echo -n "Введите Room ID Телемоста (например, 16641669958741): "
        read ROOM_ID < /dev/tty
        if [[ -z "$ROOM_ID" ]]; then
            echo -e "${RED}Ошибка: Room ID не может быть пустым.${NC}"
        fi
    done
fi

if [[ -z "$BOT_TOKEN" ]]; then
    echo -n "Введите Telegram Bot Token (от @BotFather): "
    read BOT_TOKEN < /dev/tty
fi

# 3. Deep purge of conflicting packages
echo -e "${YELLOW}--- [1/5] Глубокая очистка старых пакетов Docker/Containerd ---${NC}"
apt-get update
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc containerd.io; do 
    apt-get purge -y $pkg || true
done
apt-get autoremove -y
apt-get clean

# 4. Install Docker using official convenience script
echo -e "${YELLOW}--- [2/5] Установка Docker через официальный скрипт ---${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
apt-get install -y docker-compose-plugin qrencode git curl jq

# 5. Clone management repo
echo -e "${YELLOW}--- [3/5] Клонирование репозитория управления ---${NC}"
cd /root
if [ -d "olcrtc-manager" ]; then
    rm -rf olcrtc-manager
fi
git clone https://github.com/domadomlab/olcrtc-vps-manager.git olcrtc-manager
cd olcrtc-manager

# 6. Create .env
echo -e "${YELLOW}--- [4/5] Настройка конфигурации .env ---${NC}"
VPS_IP=$(hostname -I | awk '{print $1}')

cat << EOF > .env
OLCRTC_MODE=srv
OLCRTC_CARRIER=telemost
OLCRTC_ROOM_ID=${ROOM_ID}
OLCRTC_KEY=71a15ca28a19ee04348634ada0e709f8bb988f86ee0baaa057328193ddb3dc8f
OLCRTC_CLIENT_ID=vps-server-01
OLCRTC_TRANSPORT=vp8channel
OLCRTC_VP8_FPS=30
OLCRTC_VP8_BATCH=2
OLCRTC_LINK=direct
OLCRTC_DNS=1.1.1.1:53
OLCRTC_DATA=/usr/share/olcrtc
OLCRTC_VPS_IP=${VPS_IP}
OLCRTC_PASS=local_installation
TELEGRAM_BOT_TOKEN=${BOT_TOKEN}
ALLOWED_CHAT_ID=
EOF

# 7. Build and Run olcRTC
echo -e "${YELLOW}--- [5/5] Сборка и запуск olcRTC ---${NC}"
if [ ! -d "/root/olcrtc" ]; then
    git clone https://github.com/openlibrecommunity/olcrtc.git /root/olcrtc
fi
cd /root/olcrtc && git pull && docker build -t olcrtc/server:local .

cd /root/olcrtc-manager
docker stop olcrtc-server 2>/dev/null || true
docker rm olcrtc-server 2>/dev/null || true
docker stop olcrtc-bot 2>/dev/null || true
docker rm olcrtc-bot 2>/dev/null || true
docker compose up -d --force-recreate --build

# Watchdog setup
cp scripts/olcrtc_watchdog_v2.sh /root/olcrtc_watchdog.sh
chmod +x /root/olcrtc_watchdog.sh
(crontab -l 2>/dev/null | grep -v 'olcrtc_watchdog' ; echo '* * * * * /root/olcrtc_watchdog.sh') | crontab -

# 8. Final output with QR Codes
echo -e "\n${GREEN}--- ✅ Установка на VPS завершена успешно! ---${NC}"

# Get Bot Username via Telegram API
BOT_USER=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | jq -r '.result.username')

URI="olcrtc://telemost?vp8channel<vp8-fps=30&vp8-batch=2>@${ROOM_ID}#71a15ca28a19ee04348634ada0e709f8bb988f86ee0baaa057328193ddb3dc8f%vps-server-01\$STABLE_VPS"
BOT_URL="https://t.me/${BOT_USER}"

echo -e "\n${BLUE}1. QR-код для Android клиента (olcRTC):${NC}"
qrencode -t ansiutf8 "$URI"
echo -e "URI: ${YELLOW}$URI${NC}"

echo -e "\n${BLUE}2. QR-код для управления (Telegram Бот):${NC}"
qrencode -t ansiutf8 "$BOT_URL"
echo -e "Бот: ${YELLOW}$BOT_URL${NC}"

echo -e "\n${YELLOW}Важно:${NC} Сначала запустите бота в Telegram, чтобы стать его владельцем."
echo -e "Для управления используйте: ${YELLOW}cd /root/olcrtc-manager && ./manage.sh${NC}"

rm /root/get-docker.sh
