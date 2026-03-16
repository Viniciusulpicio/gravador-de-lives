#!/bin/bash

# --- CONFIGURAÇÕES ---
URL_ALVO="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
REMOTE_NAME="${NOME_DO_REMOTO:-MeuDrive}"
DRIVE_FOLDER="${FOLDER_ID:-1vQiWhlXTo9sJuEtCjwfUqwoV_K2Gh3Yl}"
TMP_DIR="/tmp/gravacao"
# Caminho absoluto para o log não se perder
LOG_FILE="/tmp/gravacao/gravacao.log"

# Garante que a pasta temporária existe antes de escrever o log
mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Monitoramento Blindado" | tee -a "$LOG_FILE"

while true; do
    echo ">>> [$(date)] Verificando a live no canal: $URL_ALVO" | tee -a "$LOG_FILE"

    yt-dlp \
            --cookies "$HOME/yt-cookies.txt" \
            --extractor-args "youtube:player-client=web_safari,web" \
            --live-from-start \
            -f "bestvideo+bestaudio/best" \
            --merge-output-format mkv \
            -o "$TMP_DIR/%(upload_date)s_%(title)s.%(ext)s" \
            "$URL_ALVO" 2>&1 | tee -a "$LOG_FILE"

    echo ">>> [$(date)] Gravação finalizada ou live offline. Verificando arquivos..." | tee -a "$LOG_FILE"

    # --- UPLOAD ---
    # Encontra apenas os vídeos recém-gravados
    ARQUIVOS_VIDEO=$(find "$TMP_DIR" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.webm" \))
    
    if [ -n "$ARQUIVOS_VIDEO" ]; then
        echo ">>> Enviando para o Google Drive..." | tee -a "$LOG_FILE"
        rclone move "$TMP_DIR" "$REMOTE_NAME:/" \
            --drive-root-folder-id "$DRIVE_FOLDER" \
            --include "*.{mp4,mkv,webm}" \
            --buffer-size 64M \
            -v 2>&1 | tee -a "$LOG_FILE"
            
        echo ">>> [$(date)] Upload concluído!" | tee -a "$LOG_FILE"
    else
        echo ">>> [$(date)] Nenhum vídeo finalizado para upload no momento." | tee -a "$LOG_FILE"
    fi

    echo ">>> Pausa de 60 segundos antes de checar novamente..." | tee -a "$LOG_FILE"
    sleep 60
done
