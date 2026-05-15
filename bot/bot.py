import telebot
import os
import subprocess
import time
import re
import logging
from telebot import types

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load configuration from environment
TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ALLOWED_CHAT_ID = os.getenv('ALLOWED_CHAT_ID')
ENV_PATH = "/app/config/.env"

bot = telebot.TeleBot(TOKEN)

def escape_md(text):
    """Escapes characters for Telegram MarkdownV2."""
    return re.sub(r'([_*\[\]()~`>#+\-=|{}.!])', r'\\\1', str(text))

def is_authorized(message):
    global ALLOWED_CHAT_ID
    uid = str(message.chat.id)
    if not ALLOWED_CHAT_ID:
        ALLOWED_CHAT_ID = uid
        update_env("ALLOWED_CHAT_ID", ALLOWED_CHAT_ID)
        logger.info(f"New owner registered: {uid}")
        return True
    return uid == str(ALLOWED_CHAT_ID)

def update_env(key, value):
    if not os.path.exists(ENV_PATH): 
        logger.error(f"ENV file not found at {ENV_PATH}")
        return
    with open(ENV_PATH, "r") as f:
        lines = f.readlines()
    new_lines = []
    found = False
    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f"{key}={value}\n")
            found = True
        else:
            new_lines.append(line)
    if not found: new_lines.append(f"{key}={value}\n")
    with open(ENV_PATH, "w") as f:
        f.writelines(new_lines)
    logger.info(f"Updated .env: {key}={value}")

def get_env(key):
    if not os.path.exists(ENV_PATH): return None
    with open(ENV_PATH, "r") as f:
        for line in f:
            if line.startswith(f"{key}="):
                return line.split("=")[1].strip()
    return None

def get_docker_stats():
    try:
        cmd = "docker stats olcrtc-server --no-stream --format '{{.NetIO}} | {{.MemUsage}} | {{.CPUPerc}}'"
        result = subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
        return result
    except Exception as e:
        logger.error(f"Error getting docker stats: {e}")
        return "N/A | N/A | N/A"

def generate_uri(custom_id=None):
    carrier = get_env("OLCRTC_CARRIER") or "telemost"
    transport = get_env("OLCRTC_TRANSPORT") or "vp8channel"
    fps = get_env("OLCRTC_VP8_FPS") or "30"
    batch = get_env("OLCRTC_VP8_BATCH") or "2"
    room = get_env("OLCRTC_ROOM_ID")
    key = get_env("OLCRTC_KEY")
    client_id = custom_id if custom_id else (get_env("OLCRTC_CLIENT_ID") or "vps-server-01")
    return f"olcrtc://{carrier}?{transport}<vp8-fps={fps}&vp8-batch={batch}>@{room}#{key}%{client_id}$STABLE_VPS"

@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    if not is_authorized(message): return
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add('📊 Статус', '📱 Мой QR', '🔄 Рестарт', '🚪 Сменить комнату', '➕ Новый пользователь')
    bot.send_message(message.chat.id, "🛸 **olcRTC Control Bot**\n\nИспользуйте кнопки для управления.", reply_markup=markup, parse_mode='Markdown')

@bot.message_handler(func=lambda message: message.text == '📊 Статус')
def status_cmd(message):
    if not is_authorized(message): return
    logger.info("Handling Status command")
    room_id = get_env("OLCRTC_ROOM_ID")
    stats = get_docker_stats()
    s_parts = stats.split(' | ')
    
    text = (
        f"✅ *Туннель активен*\n"
        f"📍 Комната: `{room_id}`\n"
        f"📈 Трафик: `{s_parts[0]}`\n"
        f"🧠 RAM: `{s_parts[1]}`\n"
        f"⚡ CPU: `{s_parts[2]}`"
    )
    bot.send_message(message.chat.id, text, parse_mode='Markdown')

@bot.message_handler(func=lambda message: message.text == '📱 Мой QR')
def qr_cmd(message):
    if not is_authorized(message): return
    logger.info("Handling My QR command")
    uri = generate_uri()
    qr_path = "/tmp/my_qr.png"
    subprocess.run(f"qrencode -o {qr_path} '{uri}'", shell=True)
    
    # We use Markdown code block for the URI which is safer than HTML escaping for this specific format
    caption = f"*Ваш основной QR\\-код:*\n`{escape_md(uri)}`"
    with open(qr_path, "rb") as photo:
        bot.send_photo(message.chat.id, photo, caption=caption, parse_mode='MarkdownV2')

@bot.message_handler(func=lambda message: message.text == '🔄 Рестарт')
def restart_cmd(message):
    if not is_authorized(message): return
    bot.send_message(message.chat.id, "🔄 Перезапускаю туннель...")
    subprocess.run("docker restart olcrtc-server", shell=True)
    bot.send_message(message.chat.id, "✅ Туннель перезапущен!")

@bot.message_handler(func=lambda message: message.text == '🚪 Сменить комнату')
def change_room_init(message):
    if not is_authorized(message): return
    msg = bot.send_message(message.chat.id, "Введите новый Room ID Телемоста:")
    bot.register_next_step_handler(msg, process_room_step)

def process_room_step(message):
    new_room = message.text.strip()
    if not re.match(r'^\d+$', new_room):
        bot.send_message(message.chat.id, "❌ Ошибка: только цифры.")
        return
    update_env("OLCRTC_ROOM_ID", new_room)
    bot.send_message(message.chat.id, f"📝 Применяю новую комнату `{new_room}`...")
    subprocess.run("cd /app/config && docker compose up -d olcrtc", shell=True)
    bot.send_message(message.chat.id, "🚀 Готово! Туннель работает в новой комнате.")

@bot.message_handler(func=lambda message: message.text == '➕ Новый пользователь')
def new_user_init(message):
    if not is_authorized(message): return
    msg = bot.send_message(message.chat.id, "Введите ID нового пользователя:")
    bot.register_next_step_handler(msg, process_new_user)

def process_new_user(message):
    user_id = message.text.strip()
    uri = generate_uri(user_id)
    qr_path = f"/tmp/qr_{user_id}.png"
    subprocess.run(f"qrencode -o {qr_path} '{uri}'", shell=True)
    caption = f"*QR\\-код для пользователя* `{escape_md(user_id)}`:\n`{escape_md(uri)}`"
    with open(qr_path, "rb") as photo:
        bot.send_photo(message.chat.id, photo, caption=caption, parse_mode='MarkdownV2')

logger.info("Bot starting...")
bot.infinity_polling()
