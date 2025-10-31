#!/bin/bash
set -e

URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@Ralisco/live}"
NOME_DO_REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
PASTA_NO_DRIVE="${PASTA_NO_DRIVE:-LivesCoisaDeNerd}"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="${PASTA_LOGS:-LogsGravacao}"
NOME_ARQUIVO_FORMATO="${NOME_ARQUIVO_FORMATO:-%(uploader)s - %(upload_date)s - %(title)s.%(ext)s}"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
RCLONE_CONFIG="--config $HOME/.config/rclone/rclone.conf"
COOKIE_FILE="$HOME/yt-cookies.txt"

mkdir -p "$DIRETORIO_TEMPORARIO"

echo ">>> Iniciando gravação: $(date)" | tee -a "$LOG_FILE"

# --- INÍCIO DA MUDANÇA ---

# Prepara o argumento de cookies
COOKIE_ARG=""
if [ -f "$COOKIE_FILE" ]; then
    echo ">>> Usando arquivo de cookies para autenticação." | tee -a "$LOG_FILE"
    COOKIE_ARG="--cookies $COOKIE_FILE"
else
    echo ">>> Arquivo de cookies não encontrado. Executando sem autenticação." | tee -a "$LOG_FILE"
fi

# Adiciona o $COOKIE_ARG ao comando do yt-dlp
# Se o arquivo não existir, $COOKIE_ARG será uma string vazia e não afetará o comando
yt-dlp $COOKIE_ARG --live-from-start --wait-for-video 1-43200 \
    -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
STATUS=${PIPESTATUS[0]}

# --- FIM DA MUDANÇA ---

if [ $STATUS -eq 0 ]; then
    echo ">>> Gravação concluída. Enviando vídeos para o Google Drive..." | tee -a "$LOG_FILE"
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG \
        --include "*.mp4" --include "*.mkv" --include "*.webm" --progress --delete-empty-src-dirs 2>&1 | tee -a "$LOG_FILE"
    echo ">>> Enviando log para o Google Drive..." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/gravacao_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG \
        --progress 2>&1 | tee -a "$LOG_FILE"
    echo ">>> Upload concluído com sucesso: $(date)" | tee -a "$LOG_FILE"
elif [ $STATUS -eq 1 ]; then
    echo ">>> Nenhuma live encontrada no período de 12 horas. Encerrando." | tee -a "$LOG_FILE"
else
    echo ">>> Ocorreu um erro durante a gravação. Código de saída: $STATUS" | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG \
        --progress 2>&1 | tee -a "$LOG_FILE"
    exit 1
fi

echo ">>> Processo finalizado: $(date)" | tee -a "$LOG_FILE"
