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

# Configurações de tempo
TEMPO_MAXIMO_ESPERA=${TEMPO_MAXIMO_ESPERA:-10800}  # 3 horas em segundos
INTERVALO_VERIFICACAO=180  # Verificar a cada 3 minutos
TEMPO_INICIO=$(date +%s)

mkdir -p "$DIRETORIO_TEMPORARIO"
mkdir -p "$(dirname "$RCLONE_CONFIG_PATH")"

# Configurar rclone
if [ -n "$RCLONE_CONFIG" ]; then
    echo "$RCLONE_CONFIG" > "$RCLONE_CONFIG_PATH"
    chmod 600 "$RCLONE_CONFIG_PATH"
fi

# === FUNÇÃO DE LOG ===
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# === FUNÇÃO DE NOTIFICAÇÃO ===
enviar_notificacao() {
    local mensagem="$1"
    if [ -n "$WHATSAPP_API_KEY" ] && [ -n "$WHATSAPP_RECEIVER_NUMBER_1" ]; then
        curl -s -X POST "https://api.callmebot.com/whatsapp.php" \
            -d "phone=$WHATSAPP_RECEIVER_NUMBER_1" \
            -d "text=$mensagem" \
            -d "apikey=$WHATSAPP_API_KEY" >/dev/null 2>&1 || true
    fi
}

# === FUNÇÃO PARA EXTRAIR URL DA LIVE ===
obter_url_live() {
    log_msg "Buscando URL da live..."
    
    # Busca a URL real da live (não a página do canal)
    LIVE_URL=$(yt-dlp --playlist-items 1 --get-url --no-warnings "$URL_DO_CANAL" 2>/dev/null | head -n 1)
    
    if [ -z "$LIVE_URL" ]; then
        return 1
    fi
    
    # Verifica se é realmente uma live ativa agora
    IS_LIVE=$(yt-dlp --skip-download --print "%(is_live)s" "$LIVE_URL" 2>/dev/null || echo "")
    
    if [ "$IS_LIVE" = "True" ]; then
        echo "$LIVE_URL"
        return 0
    fi
    
    return 1
}

# === FUNÇÃO PARA OBTER INFO DA LIVE ===
obter_info_live() {
    local url="$1"
    yt-dlp --skip-download --print "%(title)s" "$url" 2>/dev/null || echo "Live sem título"
}

# === INÍCIO DO PROCESSO ===
log_msg "=========================================="
log_msg "🎥 Iniciando monitoramento de lives"
log_msg "Canal: $URL_DO_CANAL"
log_msg "Tempo máximo: $((TEMPO_MAXIMO_ESPERA / 3600))h"
log_msg "=========================================="

enviar_notificacao "🎥 Monitoramento iniciado - Coisa de Nerd"

# === LOOP DE VERIFICAÇÃO ===
TENTATIVA=0
LIVE_URL=""

while true; do
    TEMPO_ATUAL=$(date +%s)
    TEMPO_DECORRIDO=$((TEMPO_ATUAL - TEMPO_INICIO))
    
    # Verifica timeout
    if [ $TEMPO_DECORRIDO -ge $TEMPO_MAXIMO_ESPERA ]; then
        log_msg "⏰ Tempo máximo de espera atingido ($((TEMPO_MAXIMO_ESPERA / 3600))h)"
        break
    fi
    
    TENTATIVA=$((TENTATIVA + 1))
    TEMPO_RESTANTE=$((TEMPO_MAXIMO_ESPERA - TEMPO_DECORRIDO))
    
    log_msg "Tentativa #$TENTATIVA (restam $((TEMPO_RESTANTE / 60)) min)"
    
    # Tenta obter URL da live
    LIVE_URL=$(obter_url_live)
    
    if [ -n "$LIVE_URL" ]; then
        TITULO=$(obter_info_live "$LIVE_URL")
        log_msg "✅ LIVE ENCONTRADA!"
        log_msg "Título: $TITULO"
        log_msg "URL: $LIVE_URL"
        break
    fi
    
    log_msg "❌ Nenhuma live ativa no momento"
    
    # Aguarda antes da próxima verificação
    if [ $TEMPO_DECORRIDO -lt $TEMPO_MAXIMO_ESPERA ]; then
        log_msg "⏳ Aguardando $((INTERVALO_VERIFICACAO / 60)) minutos..."
        sleep $INTERVALO_VERIFICACAO
    fi
done

# === VERIFICAR SE ENCONTROU LIVE ===
if [ -z "$LIVE_URL" ]; then
    log_msg "=========================================="
    log_msg "❌ Nenhuma live encontrada no período"
    log_msg "=========================================="
    enviar_notificacao "❌ Sem live hoje - Coisa de Nerd"
    
    # Upload do log
    rclone copy "$LOG_FILE" \
        "$NOME_DO_REMOTO:$PASTA_LOGS/sem_live_$(date +%Y%m%d_%H%M%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
    
    exit 0
fi

# === GRAVAR A LIVE ===
log_msg "=========================================="
log_msg "🔴 INICIANDO GRAVAÇÃO"
log_msg "=========================================="

enviar_notificacao "🔴 GRAVAÇÃO INICIADA! - $TITULO"

# Usar a URL específica da live (não a página do canal)
yt-dlp \
  --live-from-start \
  --no-part \
  --concurrent-fragments 3 \
  --format "best[ext=mp4]/best" \
  --retries 10 \
  --fragment-retries 10 \
  --output "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
  "$LIVE_URL" 2>&1 | tee -a "$LOG_FILE"

STATUS=${PIPESTATUS[0]}

# === PROCESSAR RESULTADO ===
if [ $STATUS -eq 0 ]; then
    log_msg "✅ Gravação finalizada com sucesso!"
    
    # Contar arquivos de vídeo
    VIDEO_COUNT=$(find "$DIRETORIO_TEMPORARIO" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" \) 2>/dev/null | wc -l)
    
    if [ "$VIDEO_COUNT" -eq 0 ]; then
        log_msg "⚠️  Nenhum arquivo de vídeo gerado"
        enviar_notificacao "⚠️  Gravação sem arquivo - Coisa de Nerd"
    else
        log_msg "📤 Enviando $VIDEO_COUNT arquivo(s) para o Drive..."
        enviar_notificacao "📤 Enviando para o Drive..."
        
        # Upload dos vídeos
        rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" \
            --config "$RCLONE_CONFIG_PATH" \
            --include "*.mp4" --include "*.mkv" --include "*.webm" \
            --progress \
            --delete-empty-src-dirs \
            --transfers 4 \
            --checkers 8 \
            2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
            log_msg "✅ Upload concluído!"
            enviar_notificacao "✅ VÍDEO NO DRIVE! - Coisa de Nerd"
        else
            log_msg "❌ Erro no upload"
            enviar_notificacao "❌ Erro no upload - Coisa de Nerd"
        fi
    fi
    
    # Upload do log de sucesso
    rclone copy "$LOG_FILE" \
        "$NOME_DO_REMOTO:$PASTA_LOGS/sucesso_$(date +%Y%m%d_%H%M%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
    
else
    log_msg "❌ Erro na gravação (código: $STATUS)"
    enviar_notificacao "❌ ERRO NA GRAVAÇÃO - código $STATUS"
    
    # Upload do log de erro
    rclone copy "$LOG_FILE" \
        "$NOME_DO_REMOTO:$PASTA_LOGS/erro_$(date +%Y%m%d_%H%M%S).log" \
        --config "$RCLONE_CONFIG_PATH" 2>&1 | tee -a "$LOG_FILE" || true
    
    exit 1
fi

# === LIMPEZA ===
log_msg "🧹 Limpando arquivos temporários..."
rm -rf "$DIRETORIO_TEMPORARIO"

log_msg "=========================================="
log_msg "✅ PROCESSO FINALIZADO"
log_msg "=========================================="

exit 0
