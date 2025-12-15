#!/bin/bash

# --- CONFIGURAÇÕES ---
HORA_LIMITE="2230"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"
NOME_ARQUIVO="%(upload_date)s - %(title)s.%(ext)s"

# User Agents rotativos (para variar a identidade)
UA_LIST=(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"
)
# Seleciona um UA aleatório no início
USER_AGENT=${UA_LIST[$RANDOM % ${#UA_LIST[@]}]}
REFERER="https://www.google.com/"

# Rclone
RCLONE_FLAGS="--config $HOME/.config/rclone/rclone.conf --transfers 4 --drive-chunk-size 32M"

mkdir -p "$DIRETORIO_TEMPORARIO"

# Controle de Cookies (Começa ligado)
USAR_COOKIES=true

# Função WhatsApp
enviar_whatsapp() {
    local MENSAGEM="$1"
    if [[ -n "$TWILIO_ACCOUNT_SID" && -n "$WHATSAPP_API_KEY" ]]; then
        curl -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json" \
        --data-urlencode "To=${WHATSAPP_RECEIVER_NUMBER_1}" \
        --data-urlencode "From=${WHATSAPP_SENDER_NUMBER}" \
        --data-urlencode "Body=$MENSAGEM" \
        -u "${TWILIO_ACCOUNT_SID}:${WHATSAPP_API_KEY}" \
        --silent > /dev/null
    fi
}

echo ">>> Iniciando monitoramento em $(date). UA: $USER_AGENT" | tee -a "$LOG_FILE"

# --- LOOP ---
while true; do
    HORA_ATUAL=$(date +%H%M)
    
    if [ "$HORA_ATUAL" -ge "$HORA_LIMITE" ]; then
        echo ">>> Horário limite ($HORA_LIMITE) atingido. Encerrando." | tee -a "$LOG_FILE"
        break
    fi

    # Monta comando de cookie
    COOKIE_CMD=""
    if [ "$USAR_COOKIES" = true ] && [ -f "$HOME/yt-cookies.txt" ]; then
        COOKIE_CMD="--cookies $HOME/yt-cookies.txt"
    fi

    echo ">>> [$(date +%H:%M:%S)] Verificando Live (Cookies: $USAR_COOKIES)..."

    # Verificação
    STATUS=$(yt-dlp $COOKIE_CMD \
        --user-agent "$USER_AGENT" \
        --referer "$REFERER" \
        --print "%(is_live)s" \
        "$URL_DO_CANAL" 2>&1)

    # --- LÓGICA DE DECISÃO ---
    if [[ "$STATUS" == *"True"* ]]; then
        echo ">>> 🔴 LIVE ON! GRAVANDO..." | tee -a "$LOG_FILE"
        enviar_whatsapp "🔴 Live Nerd ON! Gravando..."

        yt-dlp $COOKIE_CMD \
            --user-agent "$USER_AGENT" \
            --live-from-start \
            --wait-for-video 15 \
            --retries 50 \
            -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
            --merge-output-format mp4 \
            -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO" \
            "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
        
        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ]; then
            echo ">>> Sucesso! Subindo..." | tee -a "$LOG_FILE"
            rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_FLAGS --include "*.mp4" --log-file="$LOG_FILE"
            enviar_whatsapp "✅ Gravado e Salvo!"
            break # Sai do loop após sucesso
        else
            echo ">>> Falha na gravação." | tee -a "$LOG_FILE"
            # Se falhou gravando, remove cookies para a próxima tentativa imediata
            USAR_COOKIES=false
            sleep 10
        fi

    # --- AQUI ESTÁ A CORREÇÃO PRINCIPAL ---
    elif [[ "$STATUS" == *"Sign in"* ]] || [[ "$STATUS" == *"bot"* ]] || [[ "$STATUS" == *"429"* ]] || [[ "$STATUS" == *"cookies"* ]]; then
        echo ">>> ⚠️  BLOQUEIO DETECTADO ($STATUS)!" | tee -a "$LOG_FILE"
        
        if [ "$USAR_COOKIES" = true ]; then
            echo ">>> Ação: Desativando cookies (eles podem estar queimados)."
            USAR_COOKIES=false
            echo ">>> Aguardando 30s para tentar sem cookies..."
            sleep 30
        else
            echo ">>> Bloqueio persiste mesmo sem cookies."
            echo ">>> Ação: Aguardando 5 MINUTOS para esfriar o IP..."
            sleep 300
        fi
        
    else
        # Sem live. Espera tempo ALEATÓRIO (entre 60s e 90s) para evitar padrão robótico
        WAIT_TIME=$((60 + RANDOM % 30))
        echo ">>> Nada ainda. Aguardando ${WAIT_TIME}s..."
        sleep $WAIT_TIME
    fi
done
