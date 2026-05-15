#!/bin/bash

# Configuration
CONTAINER_NAME="olcrtc-server"
LOG_FILE="/root/watchdog_v2.log"
MAX_LOG_LINES=2000

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Ensure log file exists
touch "$LOG_FILE"

# 1. Check if docker is even running
if ! systemctl is-active --quiet docker; then
    log "CRITICAL: Docker daemon is down. Attempting to start..."
    systemctl start docker
    sleep 5
fi

# 2. Check if container exists and is running
STATUS=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)

if [ "$STATUS" != "true" ]; then
    log "Container $CONTAINER_NAME is not running (Status: $STATUS). Restarting..."
    docker restart "$CONTAINER_NAME"
    exit 0
fi

# 3. Smart Log Analysis (looking for stall patterns)
RECENT_LOGS=$(docker logs --tail 30 "$CONTAINER_NAME" 2>&1)

if echo "$RECENT_LOGS" | grep -q "tearing down smux session"; then
    RECONNECT_COUNT=$(echo "$RECENT_LOGS" | grep -c "tearing down smux session")
    if [ "$RECONNECT_COUNT" -gt 5 ]; then
        log "Detected SMUX reconnect loop ($RECONNECT_COUNT times). Forcing restart..."
        docker restart "$CONTAINER_NAME"
        exit 0
    fi
fi

if echo "$RECENT_LOGS" | grep -qE "websocket: close 4010|websocket: close 4009|ConferenceNotFound"; then
    log "Carrier (Telemost) connection lost or conference expired. Restarting..."
    docker restart "$CONTAINER_NAME"
    exit 0
fi

# 4. Cleanup log file
CURRENT_LINES=$(wc -l < "$LOG_FILE")
if [ "$CURRENT_LINES" -gt "$MAX_LOG_LINES" ]; then
    sed -i '1,500d' "$LOG_FILE"
fi
