#!/bin/bash
set -e

# --------------------------
# Configurações
# --------------------------
URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@guilherme6231/live}"
NOME_DO_REMOTO="MeuDrive"
PASTA_NO_DRIVE="LivesCoisaDeNerd"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="LogsGravacao"
NOME_ARQUIVO_FORMATO="%(uploader)s - %(upload_date)s - %(title)s.%(ext)s"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
RCLONE_CONFIG="--config $HOME/rclone/drive_config.conf"

mkdir -p "$DIRETORIO_TEMPORARIO"

echo ">>> Iniciando gravação: $(date)" | tee -a "$LOG_FILE"

# --------------------------
# Função de gravação e upload
# --------------------------
yt-dlp --live-from-start --wait-for-video 1-43200 \
    -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
STATUS=${PIPESTATUS[0]}

if [ $STATUS -eq 0 ]; then
    echo ">>> Gravação concluída. Enviando vídeos para o Google Drive..." | tee -a "$LOG_FILE"

    # Upload dos vídeos
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG \
        --include "*.mp4" --include "*.mkv" --include "*.webm" --progress --delete-empty-src-dirs 2>&1 | tee -a "$LOG_FILE"

    # Upload do log
    echo ">>> Enviando log para o Google Drive..." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/gravacao_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG \
        --progress 2>&1 | tee -a "$LOG_FILE"

    echo ">>> Upload concluído com sucesso: $(date)" | tee -a "$LOG_FILE"

elif [ $STATUS -eq 1 ]; then
    echo ">>> Nenhuma live encontrada no período de 12 horas. Encerrando." | tee -a "$LOG_FILE"
else
    echo ">>> Ocorreu um erro durante a gravação. Código de saída: $STATUS" | tee -a "$LOG_FILE"
    # Tenta enviar log mesmo em caso de erro
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG \
        --progress 2>&1 | tee -a "$LOG_FILE"
    exit 1
fi

echo ">>> Processo finalizado: $(date)" | tee -a "$LOG_FILE"
