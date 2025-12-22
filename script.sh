#!/bin/bash
# Script de Gravação Blindado v3
# Correção: Faz upload mesmo se o yt-dlp der erro no final (comum em lives)

# --- CONFIGURAÇÕES ---
URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
NOME_DO_REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
PASTA_NO_DRIVE="${PASTA_NO_DRIVE:-LivesCoisaDeNerd}"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="${PASTA_LOGS:-LogsGravacao}"
NOME_ARQUIVO_FORMATO="${NOME_ARQUIVO_FORMATO:-%(uploader)s - %(upload_date)s - %(title)s.%(ext)s}"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
RCLONE_CONFIG_FLAGS="--config $HOME/.config/rclone/rclone.conf --transfers 4" 
COOKIE_FILE="$HOME/yt-cookies.txt"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

mkdir -p "$DIRETORIO_TEMPORARIO"
echo ">>> Iniciando script: $(date)" | tee -a "$LOG_FILE"

# --- CONFIGURAÇÃO DE COOKIES ---
COOKIE_ARG=""
if [ -f "$COOKIE_FILE" ]; then
    echo ">>> Usando arquivo de cookies." | tee -a "$LOG_FILE"
    COOKIE_ARG="--cookies $COOKIE_FILE"
else
    echo ">>> AVISO: Sem cookies. Risco de bloqueio." | tee -a "$LOG_FILE"
fi

# --- 1. MONITORAMENTO ---
MAX_RETRIES=120
FOUND_LIVE=0

echo ">>> Procurando live..." | tee -a "$LOG_FILE"

for ((i=1; i<=MAX_RETRIES; i++)); do
    CHECK_OUTPUT=$(yt-dlp $COOKIE_ARG --user-agent "$USER_AGENT" --print is_live "$URL_DO_CANAL" 2>&1)
    CLEAN_OUTPUT=$(echo "$CHECK_OUTPUT" | tr -d '\n' | tr -d '\r' | sed 's/ //g')

    if [[ "$CLEAN_OUTPUT" == *"True"* ]]; then
        echo ">>> 🔴 LIVE ENCONTRADA! Iniciando..." | tee -a "$LOG_FILE"
        FOUND_LIVE=1
        break
    elif [[ "$CHECK_OUTPUT" == *"cookies are no longer valid"* ]]; then
        echo ">>> ❌ COOKIES EXPIRADOS. Tentando sem cookies..." | tee -a "$LOG_FILE"
        COOKIE_ARG=""
        continue 
    elif [[ "$CHECK_OUTPUT" == *"Sign in"* ]] || [[ "$CHECK_OUTPUT" == *"bot"* ]]; then
        echo ">>> ⚠️  BLOQUEIO DETECTADO. Esfriando 60s..." | tee -a "$LOG_FILE"
        sleep 60
    else
        echo ">>> [$i/$MAX_RETRIES] Sem live. Aguardando 60s..."
        sleep 60
    fi
done

# --- 2. GRAVAÇÃO ---
if [ $FOUND_LIVE -eq 1 ]; then
    # Adicionamos --retries infinite e --fragment-retries infinite para evitar quebras de rede
    yt-dlp $COOKIE_ARG \
        --user-agent "$USER_AGENT" \
        --live-from-start \
        --retries infinite \
        --fragment-retries infinite \
        --ignore-errors \
        --merge-output-format mkv \
        -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
        "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
    
    # NÃO confiamos mais apenas no código de saída ($?) do yt-dlp
else
    echo ">>> Tempo esgotado (Monitoramento)." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sem_live_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 0
fi

# --- 3. VERIFICAÇÃO INTELIGENTE DE SUCESSO ---
# Verificamos se existe algum arquivo de vídeo maior que 1KB na pasta
VIDEO_CRIADO=$(find "$DIRETORIO_TEMPORARIO" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.webm" \) -size +1k | head -n 1)

if [ -n "$VIDEO_CRIADO" ]; then
    echo ">>> ✅ VÍDEO DETECTADO: $VIDEO_CRIADO" | tee -a "$LOG_FILE"
    echo ">>> Iniciando Upload (mesmo se o yt-dlp reclamou)..." | tee -a "$LOG_FILE"
    
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG_FLAGS \
        --include "*.mp4" --include "*.mkv" --include "*.webm" \
        --delete-empty-src-dirs \
        --progress 2>&1 | tee -a "$LOG_FILE"
    
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sucesso_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG_FLAGS
    echo ">>> Processo concluído com sucesso."
else
    echo ">>> ❌ ERRO CRÍTICO: O yt-dlp terminou mas NENHUM vídeo foi encontrado." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_gravacao_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 1
fi
