#!/bin/bash

# --- CONFIGURAÇÕES (Puxando do YAML ou Defaults) ---
URL_ALVO="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
# ID da pasta que você enviou anteriormente
FOLDER_ID="1vQiWhlXTo9sJuEtCjwfUqwoV_K2Gh3Yl"
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"
COOKIE_FILE="$HOME/yt-cookies.txt"

# User-Agent atualizado para simular navegador real
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando monitoramento da live..." | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO ROBUSTA ---
MAX_RETRIES=120
FOUND_LIVE=0
URL_DIRETA=""

for ((i=1; i<=MAX_RETRIES; i++)); do
    # Tenta obter o ID do vídeo. O cliente 'android' é menos propenso a captchas
    VIDEO_ID=$(yt-dlp --user-agent "$UA" \
        --extractor-args "youtube:player-client=android,web" \
        --get-id "$URL_ALVO" 2>/dev/null)

    if [ -n "$VIDEO_ID" ] && [ ${#VIDEO_ID} -eq 11 ]; then
        echo ">>> [🔴 LIVE ONLINE] ID encontrado: $VIDEO_ID" | tee -a "$LOG_FILE"
        URL_DIRETA="https://www.youtube.com/watch?v=$VIDEO_ID"
        FOUND_LIVE=1
        break
    else
        echo ">>> [$i/$MAX_RETRIES] Canal offline ou oculto. Aguardando 60s..."
        sleep 60
    fi
done

# --- 2. EXECUÇÃO DA GRAVAÇÃO ---
if [ $FOUND_LIVE -eq 1 ]; then
    echo ">>> Gravando: $URL_DIRETA" | tee -a "$LOG_FILE"
    
    # Flags de resiliência para evitar quebras de stream
    yt-dlp \
        ${YOUTUBE_COOKIES:+--cookies "$COOKIE_FILE"} \
        --user-agent "$UA" \
        --extractor-args "youtube:player-client=android,web" \
        --live-from-start \
        --no-part \
        --wait-for-video 15 \
        --retry-sleep 10 \
        --retries infinite \
        --fragment-retries infinite \
        --merge-output-format mkv \
        -o "$TMP_DIR/%(uploader)s - %(title)s.%(ext)s" \
        "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"
else
    echo ">>> [ENCERRADO] Nenhuma live encontrada após as tentativas." | tee -a "$LOG_FILE"
fi

# --- 3. UPLOAD PARA O DRIVE ---
# Verificamos se há arquivos de vídeo antes de tentar o upload
if ls "$TMP_DIR"/*.{mkv,mp4,webm} >/dev/null 2>&1; then
    echo ">>> Enviando arquivos para o Google Drive..." | tee -a "$LOG_FILE"
    
    rclone move "$TMP_DIR" "$REMOTO:/" \
        --drive-root-folder-id "$FOLDER_ID" \
        --include "*.{mp4,mkv,webm}" \
        --buffer-size 64M \
        --drive-chunk-size 64M \
        --progress | tee -a "$LOG_FILE"
        
    echo ">>> Upload concluído!" | tee -a "$LOG_FILE"
else
    echo ">>> Nenhum arquivo de vídeo encontrado para upload." | tee -a "$LOG_FILE"
fi

# Envia o log para o drive também para você conferir depois
rclone copy "$LOG_FILE" "$REMOTO:/" --drive-root-folder-id "$FOLDER_ID"
