#!/bin/bash

# --- CONFIGURAÇÕES ---
URL_ALVO="${URL_DO_CANAL}"
REMOTE_NAME="${NOME_DO_REMOTO}"
DRIVE_FOLDER="${FOLDER_ID}"
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"
COOKIE_PATH="$HOME/yt-cookies.txt"

# User-Agent de um iPad para maior aceitação do YouTube em data centers
UA="Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Gravação Blindada v6" | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO ---
VIDEO_ID=$(curl -sL "$URL_ALVO" | grep -oP '"videoId":"\K[^"]+' | head -n 1)

if [ -z "$VIDEO_ID" ]; then
    echo ">>> ERRO: Live não encontrada. Verifique se o canal está online." | tee -a "$LOG_FILE"
    exit 0
fi

URL_DIRETA="https://www.youtube.com/watch?v=$VIDEO_ID"
echo ">>> Live detectada: $URL_DIRETA" | tee -a "$LOG_FILE"

# --- 2. GRAVAÇÃO ---
# Forçamos o uso do Deno e o cliente 'tv' que é menos bloqueado
yt-dlp \
    --cookies "$COOKIE_PATH" \
    --user-agent "$UA" \
    --js-runtimes "deno" \
    --extractor-args "youtube:player-client=tv,web,ios" \
    --live-from-start \
    --no-part \
    --wait-for-video 10 \
    -f "bestvideo+bestaudio/best" \
    --merge-output-format mkv \
    -o "$TMP_DIR/%(title)s.%(ext)s" \
    "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"

# --- 3. UPLOAD ---
if ls "$TMP_DIR"/*.{mkv,mp4,webm} >/dev/null 2>&1; then
    echo ">>> Enviando para o Google Drive..." | tee -a "$LOG_FILE"
    rclone move "$TMP_DIR" "$REMOTE_NAME:/" \
        --drive-root-folder-id "$DRIVE_FOLDER" \
        --include "*.{mp4,mkv,webm}" \
        --buffer-size 64M \
        --progress | tee -a "$LOG_FILE"
else
    echo ">>> Nenhum arquivo gerado para upload." | tee -a "$LOG_FILE"
fi

# Upload do Log
rclone copy "$LOG_FILE" "$REMOTE_NAME:/" --drive-root-folder-id "$DRIVE_FOLDER"
