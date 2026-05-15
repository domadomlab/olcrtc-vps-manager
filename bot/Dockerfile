FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    docker.io \
    qrencode \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install python dependencies
RUN pip install --no-cache-dir pyTelegramBotAPI

COPY bot.py .

CMD ["python", "bot.py"]
