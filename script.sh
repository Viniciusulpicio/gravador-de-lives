#!/bin/bash

# --- VARIÁVEIS ---
URL_ALVO="${URL_DO_CANAL}"
REMOTE_NAME="${NOME_DO_REMOTO}"
DRIVE_FOLDER="${FOLDER_ID}"
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"
COOKIE_PATH="$HOME/yt-cookies.txt"
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Script v5 (JS-Deno + iOS Client)" | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO DA LIVE ---
# Usamos curl para pegar o ID sem alertar o sistema de bot do yt-dlp no início
echo ">>> Buscando ID da live..." | tee -a "$LOG_FILE"
VIDEO_ID=$(curl -sL "$URL_ALVO" | grep -oP '"videoId":"\K[^"]+' | head -n 1)

if [ -z "$VIDEO_ID" ]; then
    echo ">>> ERRO: Não foi possível detectar a live. O canal pode estar offline." | tee -a "$LOG_FILE"
    exit 0
fi

URL_DIRETA="https://www.youtube.com/watch?v=$VIDEO_ID"
echo ">>> Live detectada: $URL_DIRETA" | tee -a "$LOG_FILE"

# --- 2. GRAVAÇÃO (BYPASS DE BOT) ---
# O segredo aqui é o --js-runtimes "deno" e o client "ios"
yt-dlp \
    --cookies "$COOKIE_PATH" \
    --js-runtimes "deno" \
    --user-agent "$UA" \
    --extractor-args "youtube:player-client=ios,web" \
    --live-from-start \
    --no-part \
    --ignore-errors \
    -f "bestvideo+bestaudio/best" \
    --merge-output-format mkv \
    -o "$TMP_DIR/%(title)s.%(ext)s" \
    "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"

# --- 3. UPLOAD ---
echo ">>> Verificando arquivos para upload..." | tee -a "$LOG_FILE"
if ls "$TMP_DIR"/*.{mkv,mp4,webm} >/dev/null 2>&1; then
    echo ">>> Enviando para o Google Drive..." | tee -a "$LOG_FILE"
    
    # O rclone move usando o ID da pasta específica
    rclone move "$TMP_DIR" "$REMOTE_NAME:/" \
        --config "$HOME/.config/rclone/rclone.conf" \
        --drive-root-folder-id "$DRIVE_FOLDER" \
        --include "*.{mp4,mkv,webm}" \
        --buffer-size 128M \
        --progress | tee -a "$LOG_FILE"
else
    echo ">>> Nenhum vídeo encontrado para upload." | tee -a "$LOG_FILE"
fi

# Envia o log final para a mesma pasta
rclone copy "$LOG_FILE" "$REMOTE_NAME:/" --config "$HOME/.config/rclone/rclone.conf" --drive-root-folder-id "$DRIVE_FOLDER"
