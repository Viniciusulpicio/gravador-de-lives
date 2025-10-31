set -e

# === CONFIGURAÇÕES ===
URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@Ralisco/streams}"
NOME_DO_REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
PASTA_NO_DRIVE="${PASTA_NO_DRIVE:-LivesCoisaDeNerd}"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="${PASTA_LOGS:-LogsGravacao}"
NOME_ARQUIVO_FORMATO="${NOME_ARQUIVO_FORMATO:-%(uploader)s - %(upload_date)s - %(title)s.%(ext)s}"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
RCLONE_CONFIG_PATH="$HOME/.config/rclone/rclone.conf"

mkdir -p "$DIRETORIO_TEMPORARIO"
mkdir -p "$(dirname "$RCLONE_CONFIG_PATH")"

echo "$RCLONE_CONFIG" > "$RCLONE_CONFIG_PATH"

echo ">>> Iniciando gravação: $(date)" | tee -a "$LOG_FILE"
echo ">>> Canal: $URL_DO_CANAL" | tee -a "$LOG_FILE"

# === GRAVAÇÃO ===
yt-dlp \
  --live-from-start \
  --hls-use-mpegts \
  --wait-for-video 21600 \
  -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
  "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"

STATUS=${PIPESTATUS[0]}

# === UPLOAD E LOGS ===
if [ $STATUS -eq 0 ]; then
    echo ">>> Gravação concluída. Enviando vídeos para o Google Drive..." | tee -a "$LOG_FILE"
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" \
        --config "$RCLONE_CONFIG_PATH" \
        --include "*.mp4" --include "*.mkv" --include "*.webm" \
        --progress --delete-empty-src-dirs 2>&1 | tee -a "$LOG_FILE"

    echo ">>> Enviando log para o Google Drive..." | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/gravacao_$(date +%Y-%m-%d_%H-%M-%S).log" \
        --config "$RCLONE_CONFIG_PATH" --progress 2>&1 | tee -a "$LOG_FILE"

    echo ">>> Upload concluído com sucesso: $(date)" | tee -a "$LOG_FILE"

elif [ $STATUS -eq 1 ]; then
    echo ">>> Nenhuma live encontrada no período configurado. Encerrando." | tee -a "$LOG_FILE"
else
    echo ">>> Ocorreu um erro durante a gravação. Código de saída: $STATUS" | tee -a "$LOG_FILE"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y-%m-%d_%H-%M-%S).log" \
        --config "$RCLONE_CONFIG_PATH" --progress 2>&1 | tee -a "$LOG_FILE"
    exit 1
fi

# === LIMPEZA FINAL ===
echo ">>> Limpando arquivos temporários..." | tee -a "$LOG_FILE"
rm -rf "$DIRETORIO_TEMPORARIO"

echo ">>> Processo finalizado: $(date)" | tee -a "$LOG_FILE"
