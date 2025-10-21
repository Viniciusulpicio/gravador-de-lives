#!/bin/bash
set -e

# --------------------------
# Configurações
# --------------------------
URL_DO_CANAL="https://www.youtube.com/@republicacoisadenerd/live"
NOME_DO_REMOTO="MeuDrive"
PASTA_NO_DRIVE="LivesCoisaDeNerd"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
NOME_ARQUIVO_FORMATO="%(uploader)s - %(upload_date)s - %(title)s.%(ext)s"
LOG_FILE="/tmp/gravacao/gravacao.log"
RCLONE_CONFIG="--config /rclone-secrets/drive_config"

mkdir -p "$DIRETORIO_TEMPORARIO"

echo ">>> Iniciando gravação: $(date)" | tee -a "$LOG_FILE"

# Função para gravação e upload
gravar_live() {
    echo ">>> yt-dlp: Escutando o canal '$URL_DO_CANAL' por até 12 horas..." | tee -a "$LOG_FILE"
    /usr/local/bin/yt-dlp --live-from-start --wait-for-video 1-43200 \
        -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
    STATUS=${PIPESTATUS[0]}

    if [ $STATUS -eq 0 ]; then
        echo ">>> Gravação concluída. Enviando vídeos para o Google Drive..." | tee -a "$LOG_FILE"
        /usr/bin/rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG \
            --include "*.mp4" --include "*.mkv" --include "*.webm" --progress --delete-empty-src-dirs 2>&1 | tee -a "$LOG_FILE"
        echo ">>> Upload concluído com sucesso: $(date)" | tee -a "$LOG_FILE"
    elif [ $STATUS -eq 1 ]; then
        echo ">>> yt-dlp: Nenhuma live encontrada no período de 12 horas. Encerrando." | tee -a "$LOG_FILE"
    else
        echo ">>> yt-dlp: Ocorreu um erro durante a gravação. Código de saída: $STATUS" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Tentar gravar com até 3 tentativas caso falhe
MAX_TENTATIVAS=3
TENTATIVA=1
while [ $TENTATIVA -le $MAX_TENTATIVAS ]; do
    echo ">>> Tentativa $TENTATIVA de $MAX_TENTATIVAS" | tee -a "$LOG_FILE"
    if gravar_live; then
        break
    else
        echo ">>> Erro detectado. Tentando novamente em 1 minuto..." | tee -a "$LOG_FILE"
        sleep 60
        ((TENTATIVA++))
    fi
done

echo ">>> Processo finalizado: $(date)" | tee -a "$LOG_FILE"
