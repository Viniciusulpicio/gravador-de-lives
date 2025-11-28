#!/bin/bash
# Removemos o 'set -e' global para evitar que o script morra se uma verificação falhar por erro de rede
# Vamos tratar erros manualmente

URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
NOME_DO_REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
PASTA_NO_DRIVE="${PASTA_NO_DRIVE:-LivesCoisaDeNerd}"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="${PASTA_LOGS:-LogsGravacao}"
NOME_ARQUIVO_FORMATO="${NOME_ARQUIVO_FORMATO:-%(uploader)s - %(upload_date)s - %(title)s.%(ext)s}"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
# Adicionei --transfers 4 para agilizar o upload
RCLONE_CONFIG_FLAGS="--config $HOME/.config/rclone/rclone.conf --transfers 4" 
COOKIE_FILE="$HOME/yt-cookies.txt"

mkdir -p "$DIRETORIO_TEMPORARIO"
echo ">>> Iniciando monitoramento: $(date)" | tee -a "$LOG_FILE"

# --- CONFIGURAÇÃO DE COOKIES ---
COOKIE_ARG=""
if [ -f "$COOKIE_FILE" ]; then
    echo ">>> Usando arquivo de cookies." | tee -a "$LOG_FILE"
    COOKIE_ARG="--cookies $COOKIE_FILE"
fi

# --- LOOP DE MONITORAMENTO (POLLING) ---
# Vamos tentar detectar a live por 2 horas (120 tentativas de 1 minuto)
# Ajuste MAX_RETRIES conforme necessário (120 min = 2 horas)
MAX_RETRIES=120
FOUND_LIVE=0

echo ">>> Verificando status da live a cada 60 segundos..." | tee -a "$LOG_FILE"

for ((i=1; i<=MAX_RETRIES; i++)); do
    # Verifica APENAS se está live, sem baixar (--flat-playlist --dump-json)
    # Ignora erros de rede temporários com || true
    IS_LIVE=$(yt-dlp $COOKIE_ARG --flat-playlist --dump-json "$URL_DO_CANAL" 2>/dev/null | grep -o '"is_live": true' || true)

    if [[ "$IS_LIVE" == *'"is_live": true'* ]]; then
        echo ">>> 🔴 LIVE DETECTADA! Iniciando gravação..." | tee -a "$LOG_FILE"
        FOUND_LIVE=1
        break
    else
        echo ">>> [$i/$MAX_RETRIES] Canal offline ou redirecionando. Aguardando 60s..."
        sleep 60
    fi
done

# --- GRAVAÇÃO ---
if [ $FOUND_LIVE -eq 1 ]; then
    # --live-from-start: Tenta pegar o início do buffer
    # --fixup never: Evita processamento demorado no final (opcional, mas bom para containers efêmeros)
    yt-dlp $COOKIE_ARG \
        --live-from-start \
        --ignore-errors \
        --merge-output-format mkv \
        -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
        "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
    
    GRAVACAO_STATUS=${PIPESTATUS[0]}
else
    echo ">>> Tempo limite de monitoramento esgotado. Nenhuma live iniciada." | tee -a "$LOG_FILE"
    # Faz upload do log mesmo sem live, para você saber que rodou
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sem_live_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 0
fi

# --- UPLOAD ---
if [ $GRAVACAO_STATUS -eq 0 ]; then
    echo ">>> Gravação finalizada. Iniciando Upload..." | tee -a "$LOG_FILE"
    
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG_FLAGS \
        --include "*.mp4" --include "*.mkv" --include "*.webm" \
        --delete-empty-src-dirs \
        --progress 2>&1 | tee -a "$LOG_FILE"

    echo ">>> Salvando Log..."
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sucesso_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG_FLAGS
    
    echo ">>> Processo concluído com sucesso."
else
    echo ">>> Erro crítico no yt-dlp durante a gravação." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_gravacao_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 1
fi
