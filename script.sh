#!/bin/bash
echo ">>> Iniciando processo de gravação e upload..."

URL_DO_CANAL="https://www.youtube.com/@republicacoisadenerd/live"
NOME_DO_REMOTO="MeuDrive" 
PASTA_NO_DRIVE="LivesCoisaDeNerd"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
NOME_ARQUIVO_FORMATO="%(uploader)s - %(upload_date)s - %(title)s.%(ext)s"

export RCLONE_CONFIG_${NOME_DO_REMOTO^^}_CONFIG="$RCLONE_CONFIG_DRIVE_CONFIG"
export RCLONE_CONFIG_${NOME_DO_REMOTO^^}_TYPE="drive"

mkdir -p "$DIRETORIO_TEMPORARIO"

echo ">>> yt-dlp: Escutando o canal '$URL_DO_CANAL' por até 12 horas a partir de agora..."
/usr/local/bin/yt-dlp --live-from-start --wait-for-video 1-43200 -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" "$URL_DO_CANAL"
STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo ">>> Gravação concluída. Enviando vídeos para o Google Drive..."
    /usr/bin/rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" --include "*.mp4" --include "*.mkv" --include "*.webm" --progress --delete-empty-src-dirs
    echo ">>> Arquivos enviados para o Google Drive. Processo finalizado."
elif [ $STATUS -eq 1 ]; then
    echo ">>> yt-dlp: Nenhuma live encontrada no período de 12 horas. Encerrando."
else
    echo ">>> yt-dlp: Ocorreu um erro durante a gravação. Código de saída: $STATUS"
fi
