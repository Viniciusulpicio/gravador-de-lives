#!/bin/bash

# --- CONFIGURAÇÕES (Preencha aqui) ---
URL_ALVO="https://www.youtube.com/@NOME_DO_CANAL/live"
REMOTE_NAME="MeuDrive" # Nome do remote configurado no rclone
DRIVE_FOLDER="ID_DA_PASTA_AQUI" # Se preferir usar o ID da pasta (opcional, veja explicação abaixo)
TMP_DIR="/tmp/gravacao"
LOG_FILE="$TMP_DIR/gravacao.log"

mkdir -p "$TMP_DIR"
echo ">>> [$(date)] Iniciando Monitoramento Blindado" | tee -a "$LOG_FILE"

# O loop infinito garante que o script fique rodando o fim de semana todo
while true; do
    echo ">>> [$(date)] Aguardando início da live no canal..." | tee -a "$LOG_FILE"

    # --- 1. DETECÇÃO E GRAVAÇÃO (Tudo via yt-dlp) ---
    # O yt-dlp possui a flag --wait-for-video que faz o polling de forma muito mais segura que o curl.
    # Removi o Deno e o cliente TV para evitar quebra de dependências e bloqueios 403.
    # Mantive a autenticação OAuth2 (muito superior aos cookies para evitar banimento de IP em VPS).
    
    yt-dlp \
        --username oauth2 --password '' \
        --live-from-start \
        --wait-for-video 300 \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mkv \
        -o "$TMP_DIR/%(upload_date)s_%(title)s.%(ext)s" \
        "$URL_ALVO" 2>&1 | tee -a "$LOG_FILE"

    # Se o yt-dlp encerrou, significa que a live acabou (ou a rede caiu).
    echo ">>> [$(date)] Gravação finalizada ou interrompida. Verificando arquivos..." | tee -a "$LOG_FILE"

    # --- 2. UPLOAD ---
    # Usamos o loop for para garantir que estamos movendo apenas os vídeos,
    # sem tentar mover a pasta inteira ou causar conflito com o log.
    
    ARQUIVOS_VIDEO=$(find "$TMP_DIR" -maxdepth 1 -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.webm" \))
    
    if [ -n "$ARQUIVOS_VIDEO" ]; then
        echo ">>> Enviando para o Google Drive..." | tee -a "$LOG_FILE"
        
        # A sintaxe padrão e mais segura do rclone é usar CaminhoDestino ou ID direto
        rclone move "$TMP_DIR" "$REMOTE_NAME:/" \
            --drive-root-folder-id "$DRIVE_FOLDER" \
            --include "*.{mp4,mkv,webm}" \
            --buffer-size 64M \
            -v 2>&1 | tee -a "$LOG_FILE"
            
        echo ">>> [$(date)] Upload concluído!" | tee -a "$LOG_FILE"
    else
        echo ">>> [$(date)] Nenhum vídeo encontrado para upload." | tee -a "$LOG_FILE"
    fi

    # Pausa de segurança de 1 minuto antes de checar o canal de novo
    # (Caso a live tenha apenas caído e o streamer vá abrir de novo em seguida)
    sleep 60
done
