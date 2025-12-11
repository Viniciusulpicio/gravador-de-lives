#!/bin/bash

# --- CONFIGURAÇÕES ---
# Define horário limite (22:30 no horário do Brasil)
HORA_LIMITE="2230"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
NOME_ARQUIVO="%(upload_date)s - %(title)s.%(ext)s"

# Configuração Anti-Bot (Finge ser um Chrome no Windows)
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
REFERER="https://www.youtube.com/"

# Configurações do Rclone
RCLONE_FLAGS="--config $HOME/.config/rclone/rclone.conf --transfers 4 --drive-chunk-size 32M"

mkdir -p "$DIRETORIO_TEMPORARIO"

# Função para enviar WhatsApp (Só se as chaves existirem)
enviar_whatsapp() {
    local MENSAGEM="$1"
    if [[ -n "$TWILIO_ACCOUNT_SID" && -n "$WHATSAPP_API_KEY" ]]; then
        curl -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json" \
        --data-urlencode "To=${WHATSAPP_RECEIVER_NUMBER_1}" \
        --data-urlencode "From=${WHATSAPP_SENDER_NUMBER}" \
        --data-urlencode "Body=$MENSAGEM" \
        -u "${TWILIO_ACCOUNT_SID}:${WHATSAPP_API_KEY}" \
        --silent > /dev/null
        echo ">>> WhatsApp enviado: $MENSAGEM"
    fi
}

echo ">>> Iniciando monitoramento em $(date)" | tee -a "$LOG_FILE"

# --- LOOP DE MONITORAMENTO ---
while true; do
    # 1. Verifica horário atual (Formato HHMM, ex: 1930)
    HORA_ATUAL=$(date +%H%M)
    
    # 2. Se passou das 22:30, encerra o script
    if [ "$HORA_ATUAL" -ge "$HORA_LIMITE" ]; then
        echo ">>> Horário limite ($HORA_LIMITE) atingido. Encerrando sem gravações." | tee -a "$LOG_FILE"
        break
    fi

    echo ">>> [$(date +%H:%M:%S)] Verificando se a live está ON..."

    # 3. Verifica se tem cookies
    COOKIE_CMD=""
    if [ -f "$HOME/yt-cookies.txt" ]; then
        COOKIE_CMD="--cookies $HOME/yt-cookies.txt"
    fi

    # 4. Pergunta ao YouTube se está ao vivo (retorna True ou False/Erro)
    # Usamos flags extras para evitar bloqueios
    STATUS=$(yt-dlp $COOKIE_CMD \
        --user-agent "$USER_AGENT" \
        --referer "$REFERER" \
        --print "%(is_live)s" \
        "$URL_DO_CANAL" 2>&1)

    # 5. Se encontrou a Live
    if [[ "$STATUS" == *"True"* ]]; then
        echo ">>> 🔴 LIVE DETECTADA! INICIANDO GRAVAÇÃO..." | tee -a "$LOG_FILE"
        enviar_whatsapp "🔴 A Live do Coisa de Nerd começou! Gravando..."

        # Comando de gravação (Robusto contra quedas)
        yt-dlp $COOKIE_CMD \
            --user-agent "$USER_AGENT" \
            --live-from-start \
            --wait-for-video 15 \
            --retries 50 \
            --fragment-retries 50 \
            -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
            --merge-output-format mp4 \
            -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO" \
            "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
        
        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ]; then
            echo ">>> Gravação concluída. Iniciando Upload..." | tee -a "$LOG_FILE"
            enviar_whatsapp "✅ Gravação concluída. Subindo para o Drive..."
            
            # Upload para o Drive
            rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_FLAGS \
                --include "*.mp4" --include "*.mkv" --log-file="$LOG_FILE"
            
            enviar_whatsapp "📁 Vídeo salvo no Drive com sucesso!"
        else
            echo ">>> Erro na gravação ou live interrompida." | tee -a "$LOG_FILE"
            # Salva o log de erro no drive
            rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y%m%d).log" $RCLONE_FLAGS
        fi
        
        # Sai do loop após gravar (para não tentar gravar a mesma live 2x)
        break

    elif [[ "$STATUS" == *"Sign in"* ]] || [[ "$STATUS" == *"429"* ]]; then
        echo ">>> ⚠️  Alerta: YouTube bloqueou o pedido temporariamente."
        # Se bloquear, espera mais tempo (2 min)
        sleep 120
    else
        # Se não tem live, espera 60 segundos e tenta de novo
        echo ">>> Nada ainda. Aguardando..."
        sleep 60
    fi
done

echo ">>> Processo finalizado."