#!/bin/bash
# Script de monitoramento e gravação de Lives do YouTube com Diagnóstico
# Versão: Auto-Correction para Cookies Expirados

# --- CONFIGURAÇÕES E VARIÁVEIS ---
URL_DO_CANAL="${URL_DO_CANAL:-https://www.youtube.com/@republicacoisadenerd/live}"
NOME_DO_REMOTO="${NOME_DO_REMOTO:-MeuDrive}"
PASTA_NO_DRIVE="${PASTA_NO_DRIVE:-LivesCoisaDeNerd}"
DIRETORIO_TEMPORARIO="/tmp/gravacao"
PASTA_LOGS="${PASTA_LOGS:-LogsGravacao}"
NOME_ARQUIVO_FORMATO="${NOME_ARQUIVO_FORMATO:-%(uploader)s - %(upload_date)s - %(title)s.%(ext)s}"
LOG_FILE="$DIRETORIO_TEMPORARIO/gravacao.log"

# Configuração do Rclone (com --transfers 4 para agilizar)
RCLONE_CONFIG_FLAGS="--config $HOME/.config/rclone/rclone.conf --transfers 4" 
COOKIE_FILE="$HOME/yt-cookies.txt"

# Cria diretório temporário
mkdir -p "$DIRETORIO_TEMPORARIO"

# Inicia log
echo ">>> Iniciando monitoramento: $(date)" | tee -a "$LOG_FILE"

# --- CONFIGURAÇÃO DE COOKIES ---
COOKIE_ARG=""
if [ -f "$COOKIE_FILE" ]; then
    echo ">>> Usando arquivo de cookies para autenticação inicial." | tee -a "$LOG_FILE"
    COOKIE_ARG="--cookies $COOKIE_FILE"
else
    echo ">>> AVISO: Arquivo de cookies não encontrado. Tentando sem autenticação." | tee -a "$LOG_FILE"
fi

# --- LOOP DE MONITORAMENTO (POLLING ROBUSTO) ---
# Tenta detectar a live por 2 horas (120 tentativas de 1 minuto)
MAX_RETRIES=120
FOUND_LIVE=0

echo ">>> Verificando status da live a cada 60 segundos..." | tee -a "$LOG_FILE"

for ((i=1; i<=MAX_RETRIES; i++)); do
    echo ">>> [Tentativa $i/$MAX_RETRIES] Consultando YouTube..."

    # Captura a saída (stdout) e erros (stderr) combinados
    # --print is_live retorna "True", "False" ou "NA"
    CHECK_OUTPUT=$(yt-dlp $COOKIE_ARG --print is_live "$URL_DO_CANAL" 2>&1)
    
    # Limpa a saída (remove quebras de linha e espaços extras) para comparação segura
    CLEAN_OUTPUT=$(echo "$CHECK_OUTPUT" | tr -d '\n' | tr -d '\r' | sed 's/ //g')

    # --- Lógica de Decisão e Recuperação ---
    
    # 1. Sucesso: Live encontrada
    if [[ "$CLEAN_OUTPUT" == *"True"* ]]; then
        echo ">>> 🔴 LIVE DETECTADA! (Status: $CLEAN_OUTPUT). Iniciando gravação..." | tee -a "$LOG_FILE"
        FOUND_LIVE=1
        break
    fi

    # 2. Erro de Acesso (Cookies podres ou Bloqueio)
    # Detecta "Sign in", "cookies are no longer valid", "bot", ou erro 429
    if [[ "$CHECK_OUTPUT" == *"cookies are no longer valid"* ]] || [[ "$CHECK_OUTPUT" == *"Sign in"* ]] || [[ "$CHECK_OUTPUT" == *"bot"* ]] || [[ "$CHECK_OUTPUT" == *"429"* ]]; then
        echo ">>> ⚠️  ALERTA: Problema de acesso detectado." | tee -a "$LOG_FILE"
        
        if [ -n "$COOKIE_ARG" ]; then
            echo ">>> DIAGNÓSTICO: Os cookies atuais parecem inválidos ou expirados." | tee -a "$LOG_FILE"
            echo ">>> AÇÃO: Desativando cookies e tentando novamente IMEDIATAMENTE (Fallback Mode)..." | tee -a "$LOG_FILE"
            COOKIE_ARG=""
            # 'continue' força o loop a rodar de novo AGORA, sem esperar 60s
            continue 
        else
            echo ">>> ERRO CRÍTICO: Bloqueio persiste mesmo sem cookies. O IP pode estar banido temporariamente." | tee -a "$LOG_FILE"
            echo ">>> Detalhe do erro: $CHECK_OUTPUT" | tee -a "$LOG_FILE"
            echo ">>> Aguardando 60s para esfriar..."
            sleep 60
        fi
    else
        # 3. Caso padrão: Live não encontrada ou canal offline (False/NA)
        echo ">>> Live não iniciada (Status: $CLEAN_OUTPUT). Aguardando 60s..."
        sleep 60
    fi
done

# --- GRAVAÇÃO ---
if [ $FOUND_LIVE -eq 1 ]; then
    echo ">>> Iniciando yt-dlp..." | tee -a "$LOG_FILE"
    
    # --live-from-start: Tenta pegar o início do buffer
    # --fixup never: Evita processamento demorado no final
    yt-dlp $COOKIE_ARG \
        --live-from-start \
        --ignore-errors \
        --merge-output-format mkv \
        -o "$DIRETORIO_TEMPORARIO/$NOME_ARQUIVO_FORMATO" \
        "$URL_DO_CANAL" 2>&1 | tee -a "$LOG_FILE"
    
    GRAVACAO_STATUS=${PIPESTATUS[0]}
else
    echo ">>> Tempo limite de monitoramento esgotado (2h). Nenhuma live iniciada." | tee -a "$LOG_FILE"
    
    # Salva o log de "sem live" para auditoria
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sem_live_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 0
fi

# --- UPLOAD ---
if [ $GRAVACAO_STATUS -eq 0 ]; then
    echo ">>> Gravação finalizada com sucesso. Iniciando Upload para o Drive..." | tee -a "$LOG_FILE"
    
    # Move os vídeos
    rclone move "$DIRETORIO_TEMPORARIO" "$NOME_DO_REMOTO:$PASTA_NO_DRIVE" $RCLONE_CONFIG_FLAGS \
        --include "*.mp4" --include "*.mkv" --include "*.webm" \
        --delete-empty-src-dirs \
        --progress 2>&1 | tee -a "$LOG_FILE"

    echo ">>> Upload dos vídeos concluído. Salvando Log final..."
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/sucesso_$(date +%Y-%m-%d_%H-%M-%S).log" $RCLONE_CONFIG_FLAGS
    
    echo ">>> Processo TOTAL concluído com sucesso."
else
    echo ">>> ❌ ERRO: O yt-dlp encerrou com erro (Código $GRAVACAO_STATUS)." | tee -a "$LOG_FILE"
    
    # Salva o log de erro
    rclone copy "$LOG_FILE" "$NOME_DO_REMOTO:$PASTA_LOGS/erro_gravacao_$(date +%Y-%m-%d).log" $RCLONE_CONFIG_FLAGS
    exit 1
fi
