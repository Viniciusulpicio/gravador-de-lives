#!/bin/bash

# --- CONFIGURAÇÕES ---
# Puxa do YAML ou usa o padrão do canal
URL_ALVO="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
FOLDER_ID="1vQiWhlXTo9sJuEtCjwfUqwoV_K2Gh3Yl"
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"
COOKIE_FILE="$HOME/yt-cookies.txt"

# User-Agent de navegador moderno
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Script de Gravação Blindado v4" | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO RESILIENTE ---
# Tenta encontrar o ID da live de 3 formas diferentes para evitar bloqueios do GitHub
MAX_RETRIES=120
FOUND_LIVE=0
URL_DIRETA=""

for ((i=1; i<=MAX_RETRIES; i++)); do
    echo ">>> [$i/$MAX_RETRIES] Verificando status da live..." | tee -a "$LOG_FILE"
    
    # Forma 1: yt-dlp usando cliente de Smart TV (menos bloqueado)
    VIDEO_ID=$(yt-dlp --user-agent "$UA" \
        --extractor-args "youtube:player-client=tv,android" \
        --get-id "$URL_ALVO" 2>/dev/null | head -n 1)

    # Forma 2: Se falhar, tenta via curl extraindo do HTML bruto (ignora bloqueios de bot do yt-dlp)
    if [ -z "$VIDEO_ID" ] || [ ${#VIDEO_ID} -ne 11 ]; then
        VIDEO_ID=$(curl -sL "$URL_ALVO" | grep -oP '"videoId":"\K[^"]+' | head -n 1)
    fi

    # Validação do ID encontrado
    if [ -n "$VIDEO_ID" ] && [ ${#VIDEO_ID} -eq 11 ]; then
        echo ">>> [🔴 LIVE ONLINE] ID detectado: $VIDEO_ID" | tee -a "$LOG_FILE"
        URL_DIRETA="https://www.youtube.com/watch?v=$VIDEO_ID"
        FOUND_LIVE=1
        break
    else
        echo ">>> Canal parece offline. Aguardando 60s..."
        sleep 60
    fi
done

# --- 2. GRAVAÇÃO ---
if [ $FOUND_LIVE -eq 1 ]; then
    echo ">>> Gravando em: $TMP_DIR" | tee -a "$LOG_FILE"
    
    # Gravando com foco em não perder dados se a conexão oscilar
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
        --ignore-errors \
        --merge-output-format mkv \
        -o "$TMP_DIR/%(uploader)s - %(title)s.%(ext)s" \
        "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"
else
    echo ">>> [ERRO] Tempo esgotado. Nenhuma live encontrada." | tee -a "$LOG_FILE"
    # Envia o log de erro para o Drive para você saber o que houve
    rclone copy "$LOG_FILE" "$REMOTO:/" --drive-root-folder-id "$FOLDER_ID"
    exit 0
fi

# --- 3. UPLOAD AUTOMÁTICO ---
if ls "$TMP_DIR"/*.{mkv,mp4,webm} >/dev/null 2>&1; then
    echo ">>> Iniciando Upload para o Google Drive..." | tee -a "$LOG_FILE"
    
    # Move os arquivos para a pasta específica usando o ID
    rclone move "$TMP_DIR" "$REMOTO:/" \
        --drive-root-folder-id "$FOLDER_ID" \
        --include "*.{mp4,mkv,webm}" \
        --buffer-size 64M \
        --drive-chunk-size 64M \
        --progress | tee -a "$LOG_FILE"
        
    echo ">>> Processo concluído com sucesso!" | tee -a "$LOG_FILE"
else
    echo ">>> [ERRO] Nenhum arquivo de vídeo foi gerado." | tee -a "$LOG_FILE"
fi

# Envia o log final
rclone copy "$LOG_FILE" "$REMOTO:/" --drive-root-folder-id "$FOLDER_ID"
