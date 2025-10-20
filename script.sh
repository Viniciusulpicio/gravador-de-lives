#!/bin/bash
echo ">>> Iniciando gravação de live..."

URL_DO_CANAL="https://www.youtube.com/@republicacoisadenerd/live"
NOME_DO_REMOTO="MeuDrive"
PASTA_NO_DRIVE="LivesCoisaDeNerd"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
NOME_ARQUIVO_FORMATO="%(uploader)s - %(upload_date)s - %(title)s.%(ext)s"

mkdir -p "$DIRETORIO_TEMPORARIO"

echo ">>> Escutando canal por até 5 horas..."
/usr/local/bin/yt-dlp --live-from-start --wait-for-video 1-18000 -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" "$URL_DO_CANAL"
STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo ">>> Live detectada e gravada."
    /usr/bin/rclone mkdir "$NOME_DO_REMOTO:$PASTA_NO_DRIVE"
    /usr/bin/rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" --include "*.mp4" --include "*.mkv" --include "*.webm" --progress --delete-empty-src-dirs
    echo ">>> Upload concluído!"
elif [ $STATUS -eq 1 ]; then
    echo ">>> Nenhuma live encontrada nas últimas 5h."
else
    echo ">>> Erro na gravação. Código: $STATUS"
fi

rm -rf "$DIRETORIO_TEMPORARIO"
echo ">>> Processo finalizado."
