ROM debian:slim
RUN apt-get update && apt-get install -y curl ffmpeg && rm -rf /var/lib/apt/lists/*
RUN curl https://rclone.org/install.sh | bash
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && chmod a+rx /usr/local/bin/yt-dlp
COPY script.sh .
RUN chmod +x ./script.sh
CMD ["./script.sh"]
