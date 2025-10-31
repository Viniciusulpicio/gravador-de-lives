#!/bin/bash
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

# Configurações de tempo (em segundos)
INTERVALO_VERIFICACAO=300   # Verificar a cada 5 minutos
TEMPO_MAXIMO_ESPERA_DEFAULT=10800 # 3 horas de espera máxima

mkdir -p "$DIRETORIO_TEMPORARIO"
mkdir -p "$(dirname "$RCLONE_CONFIG_PATH")"

# === FUNÇÃO DE LOG ===
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# === CORREÇÃO: CONVERTER TEMPO DE HORAS PARA SEGUNDOS ===
# O workflow passa TEMPO_MAXIMO_ESPERA como '3' (horas)
# O script precisa de segundos para o cálculo de tentativas.

if [ -n "$TEMPO_MAXIMO_ESPERA" ] && [ "$TEMPO_MAXIMO_ESPERA" -lt 1000 ]; then
    # Se o número for pequeno (ex: '3'), assume que são horas e converte
    log_msg "Valor de TEMPO_MAXIMO_ESPERA ($TEMPO_MAXIMO_ESPERA) detectado como horas. Convertendo para segundos."
    TEMPO_MAXIMO_ESPERA=$((TEMPO_MAXIMO_ESPERA * 3600))
else
    # Caso contrário, usa o valor passado (se for grande) ou o padrão
    TEMPO_MAXIMO_ESPERA=${TEMPO_MAXIMO_ESPERA:-$TEMPO_MAXIMO_ESPERA_DEFAULT}
fi

TENTATIVAS_MAXIMAS=$((TEMPO_MAXIMO_ESPERA / INTERVALO_VERIFICACAO))
# ========================================================


# Configurar rclone - verifica se o conteúdo está em variável de ambiente
# === CORREÇÃO: Variável renomeada para RCLONE_CONFIG_CONTENT ===
if [ -n "$RCLONE_CONFIG_CONTENT" ]; then
    echo "$RCLONE_CONFIG_CONTENT" > "$RCLONE_CONFIG_PATH"
    chmod 600 "$RCLONE_CONFIG_PATH"
    log_msg "Configuração do rclone criada em $RCLONE_CONFIG_PATH"
else
    log_msg "AVISO: Variável RCLONE_CONFIG_CONTENT não definida. Rclone pode falhar."
fi
# =============================================================

# Verificar se o arquivo de configuração existe
if [ ! -f "$RCLONE_CONFIG_PATH" ]; then
    log_msg "ERRO: Arquivo de configuração do rclone não encontrado em $RCLONE_CONFIG_PATH"
    exit 1
fi

# === FUNÇÃO DE NOTIFICAÇÃO WHATSAPP ===
enviar_notificacao() {
    local mensagem="$1"
    
    if [ -n "$WHATSAPP_API_KEY" ] && [ -n "$WHATSAPP_RECEIVER_NUMBER_1" ]; then
        curl -X POST "https://api.callmebot.com/whatsapp.php" \
            -d "phone=$WHATSAPP_RECEIVER_NUMBER_1" \
            -d "text=$(echo "$mensagem" | jq -sRr @uri)" \
            -d "apikey=$WHATSAPP_API_KEY" \
            2>/dev/null || true
    fi
}

# === VERIFICAR SE HÁ LIVE ATIVA ===
verificar_live_ativa() {
    log_msg "Verificando se há live ativa..."
    
    # Tenta obter informações da live sem baixar
    INFO=$(yt-dlp --skip-download --print "%(is_live)s|%(title)s" "$URL_DO_CANAL" 2>/dev/null || echo "")
    
    if [ -z "$INFO" ]; then
        return 1  # Nenhuma live encontrada
    fi
    
    IS_LIVE=$(echo "$INFO" | cut -d'|' -f1)
    TITULO=$(echo "$INFO" | cut -d'|' -f2)
    
    if [ "$IS_LIVE" = "True" ]; then
        log_msg "✓ Live encontrada: $TITULO"
        return 0  # Live está ativa
    else
        return 1  # Não é uma live ativa
    fi
}

# === INÍCIO DO PROCESSO ===
log_msg "=========================================="
log_msg "Iniciando monitoramento de lives"
log_msg "Canal: $URL_DO_CANAL"
log_msg "Tempo máximo de espera: $((TEMPO_MAXIMO_ESPERA / 3600))h ($TENTATIVAS_MAXIMAS tentativas)"
log_msg "Verificando remotas do rclone:"
rclone listremotes --config "$RCLONE_CONFIG_PATH" | tee -a "$LOG_FILE"
log_msg "=========================================="

enviar_notificacao "🎥 Monitoramento iniciado - Canal: Coisa de Nerd"

# === LOOP DE VERIFICAÇÃO ===
TENTATIVA=0
LIVE_ENCONTRADA=false

while [ $TENTATIVA -lt $TENTATIVAS_MAXIMAS ]; do
    TENTATIVA=$((TENTATIVA + 1))
    log_msg "Tentativa $TENTATIVA de $TENTATIVAS_MAXIMAS"
    
    if verificar_live_ativa; then
        LIVE_ENCONTRADA=true
        break
    fi
    
    if [ $TENTATIVA -lt $TENTATIVAS_MAXIMAS ]; then
        log_msg "Nenhuma live ativa. Aguardando $((INTERVALO_VERIFICACAO / 60)) minutos..."
        sleep "$INTERVALO_VERIFICACAO"
    fi
done

# === PROCESSAR RESULTADO ===
if [ "$LIVE_ENCONTRADA" = false ]; then
    log_msg "❌ Nenhuma live encontrada após $((TEMPO_MAXIMO_ESPERA / 3600))h de espera"
    enviar_notificacao "❌ Nenhuma live encontrada hoje - Coisa de Nerd"
    
    # Upload do log de "sem live"
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sem_live_$(date +%Y-%m-%d_%H-%M-%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
        
    exit 0  # Sai com sucesso (não é erro, apenas não havia live)
fi

# === GRAVAÇÃO ===
log_msg "=========================================="
log_msg "Iniciando gravação da live..."
log_msg "=========================================="

enviar_notificacao "🔴 Gravação iniciada! - Coisa de Nerd"

yt-dlp \
  --live-from-start \
  --hls-use-mpegts \
  --no-part \
  --format "best[ext=mp4]/best" \
  -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
  "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"

STATUS=${PIPESTATUS[0]}

# === PROCESSAMENTO PÓS-GRAVAÇÃO ===
if [ $STATUS -eq 0 ]; then
    log_msg "✓ Gravação concluída com sucesso!"
    
    # Verificar se há arquivos de vídeo
    VIDEO_COUNT=$(find "$DIRETORIO_TEMPORARIO" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) | wc -l)
    
    if [ "$VIDEO_COUNT" -eq 0 ]; then
        log_msg "⚠ Nenhum arquivo de vídeo encontrado para upload"
        enviar_notificacao "⚠ Gravação sem vídeo - Coisa de Nerd"
    else
        log_msg "Enviando $VIDEO_COUNT arquivo(s) para o Google Drive..."
        enviar_notificacao "📤 Enviando vídeo para o Drive - Coisa de Nerd"
        
        rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" \
            --config "$RCLONE_CONFIG_PATH" \
            --include "*.mp4" --include "*.mkv" --include "*.webm" \
            --progress --delete-empty-src-dirs 2>&1 | tee -a "$LOG_FILE"
            
        log_msg "✓ Upload de vídeo concluído!"
        enviar_notificacao "✅ Vídeo salvo no Drive com sucesso! - Coisa de Nerd"
    fi
    
    # Upload do log
    log_msg "Enviando log para o Google Drive..."
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sucesso_$(date +%Y-%m-%d_%H-%M-%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
        
else
    log_msg "❌ Erro durante a gravação. Código: $STATUS"
    enviar_notificacao "❌ Erro na gravação - Código: $STATUS - Coisa de Nerd"
    
    # Upload do log de erro
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y-%m-%d_%H-%M-%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
        
    exit 1
fi

# === LIMPEZA FINAL ===
log_msg "Limpando arquivos temporários..."
rm -rf "$DIRETORIO_TEMPORARIO"
log_msg "=========================================="
log_msg "Processo finalizado com sucesso!"
log_msg "=========================================="

exit 0
