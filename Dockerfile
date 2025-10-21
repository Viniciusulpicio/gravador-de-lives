FROM debian:slim

# Instala dependências
RUN apt-get update && apt-get install -y \
    curl \
    ffmpeg \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Instala rclone
RUN curl https://rclone.org/install.sh | bash

# Instala yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Copia o script de gravação
COPY script.sh .
RUN chmod +x ./script.sh

# Comando padrão
CMD ["./script.sh"]
