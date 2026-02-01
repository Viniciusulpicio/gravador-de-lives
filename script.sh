#!/bin/bash

# --- CONFIGURAÇÕES ---
# Usamos a URL do canal, mas o script vai extrair o ID real da live
URL_CANAL="https://www.youtube.com/@republicacoisadenerd/live"
ID_PASTA_DRIVE="1vQiWhlXTo9sJuEtCjwfUqwoV_K2Gh3Yl"
REMOTO_RCLONE="remote" # Nome que você deu no rclone config

DIRETORIO_TEMPORARIO="/tmp/gravacao"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
COOKIE_FILE="$HOME/yt-cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

mkdir -p "$DIRETORIO_TEMPORARIO"
echo ">>> Iniciando monitoramento: $(date)" | tee -a "$LOG_FILE"

# --- 1. DETECÇÃO ROBUSTA ---
MAX_RETRIES=120
FOUND_ID=""

for ((i=1; i<=MAX_RETRIES; i++)); do
    echo ">>> [$i/$MAX_RETRIES] Verificando se @republicacoisadenerd está ao vivo..."
    
    # Tentamos pegar o ID do vídeo diretamente. Se houver live, ele retorna o ID de 11 caracteres.
    FOUND_ID=$(yt-dlp --cookies "$COOKIE_FILE" --user-agent "$USER_AGENT" --get-id "$URL_CANAL" 2>/dev/null | head -n 1)

    if [[ -n "$FOUND_ID" && ${#FOUND_ID} -ge 10 ]]; then
        echo ">>> 🔴 LIVE DETECTADA! ID do vídeo: $FOUND_ID" | tee -a "$LOG_FILE"
        break
    fi

    echo ">>> Ainda offline. Aguardando 60s..."
    sleep 60
done

if [ -z "$FOUND_ID" ]; then
    echo ">>> ❌ Tempo esgotado. Nenhuma live encontrada." | tee -a "$LOG_FILE"
    exit 0
fi

# --- 2. GRAVAÇÃO ---
# Agora usamos o ID direto, o que evita erros de redirecionamento
URL_DIRETA="https://www.youtube.com/watch?v=$FOUND_ID"

echo ">>> Iniciando gravação da URL: $URL_DIRETA" | tee -a "$LOG_FILE"

yt-dlp --cookies "$COOKIE_FILE" \
    --user-agent "$USER_AGENT" \
    --live-from-start \
    --wait-for-video 10 \
    --retries infinite \
    --fragment-retries infinite \
    --no-part \
    --ignore-errors \
    -o "$DIRETORIO_TEMPORARIO/%(title)s.%(ext)s" \
    "$URL_DIRETA" 2>&1 | tee -a "$LOG_FILE"

# --- 3. UPLOAD PARA A PASTA ESPECÍFICA ---
echo ">>> Iniciando upload para a pasta do Drive..." | tee -a "$LOG_FILE"

# O rclone move tudo que foi baixado para o ID da pasta que você passou
rclone move "$DIRETORIO_TEMPORARIO" "$REMOTO_RCLONE:/" \
    --drive-root-folder-id "$ID_PASTA_DRIVE" \
    --include "*.mp4" --include "*.mkv" --include "*.webm" \
    --buffer-size 64M \
    --progress 2>&1 | tee -a "$LOG_FILE"

echo ">>> Processo finalizado em: $(date)" | tee -a "$LOG_FILE"
