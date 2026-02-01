#!/bin/bash

# --- CONFIGURAÇÕES ---
URL_ALVO="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
FOLDER_ID="${FOLDER_ID:-1vQiWhlXTo9sJuEtCjwfUqwoV_K2Gh3Yl}"
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"
COOKIE_FILE="$HOME/yt-cookies.txt"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Gravação" | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO DA LIVE ---
MAX_RETRIES=120
FOUND_LIVE=0
VIDEO_ID=""

for ((i=1; i<=MAX_RETRIES; i++)); do
    # Tenta obter o ID via curl (mais resistente a bloqueios de bot)
    VIDEO_ID=$(curl -sL "$URL_ALVO" | grep -oP '"videoId":"\K[^"]+' | head -n 1)
    
    if [ -n "$VIDEO_ID" ] && [ ${#VIDEO_ID} -eq 11 ]; then
        echo ">>> [🔴 LIVE ONLINE] ID: $VIDEO_ID" | tee -a "$LOG_FILE"
        FOUND_LIVE=1
        break
    else
        echo ">>> [$i/$MAX_RETRIES] Aguardando live..."
        sleep 60
    fi
done

# --- 2. EXECUÇÃO DO YT-DLP ---
if [ $FOUND_LIVE -eq 1 ]; then
    URL_DIRETA="https://www.youtube.com/watch?v=$VIDEO_ID"
    
    # Adicionamos -f "best" para garantir que ele pegue o vídeo mesmo com problemas de n-challenge
    yt-dlp \
        --cookies "$COOKIE_FILE" \
        --user-agent "$UA" \
        --live-from-start \
        --no-part \
        --ignore-errors \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mkv \
        -o "$TMP_DIR/%(title)s.%(ext)s" \
        "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"
else
    echo ">>> Nenhuma live detectada." | tee -a "$LOG_FILE"
    exit 0
fi

# --- 3. UPLOAD VIA RCLONE ---
# Usamos --config explicitamente para evitar que ele tente usar variáveis de ambiente zoadas
if ls "$TMP_DIR"/*.{mkv,mp4,webm} >/dev/null 2>&1; then
    echo ">>> Iniciando Upload..." | tee -a "$LOG_FILE"
    
    rclone move "$TMP_DIR" "$REMOTO:/" \
        --config "$HOME/.config/rclone/rclone.conf" \
        --drive-root-folder-id "$FOLDER_ID" \
        --include "*.{mp4,mkv,webm}" \
        --progress | tee -a "$LOG_FILE"
fi

# Salva o log no Drive
rclone copy "$LOG_FILE" "$REMOTO:/" --config "$HOME/.config/rclone/rclone.conf" --drive-root-folder-id "$FOLDER_ID"
