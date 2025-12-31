FROM alpine:3.19

# Instalar dependencias
RUN apk add --no-cache \
    bash \
    docker-cli \
    cifs-utils \
    python3 \
    py3-pip \
    tzdata \
    curl \
    jq

# Configurar timezone
ENV TZ=Europe/Madrid
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Crear directorio de trabajo
WORKDIR /app

# Copiar scripts
COPY scripts/ /app/scripts/
COPY config.env /app/config.env

# Dar permisos de ejecución
RUN chmod +x /app/scripts/*.sh

# Crear directorio para logs
RUN mkdir -p /app/logs

# Script de entrada
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Variables de entorno por defecto
ENV BACKUP_SCHEDULE="0 3 * * 0"
ENV QNAP_HOST="192.168.1.140"
ENV QNAP_SHARE="JOAQUIN"
ENV QNAP_USER="CARMENVELASCO\\joaquin"
ENV QNAP_MOUNT_POINT="/mnt/qnap"

ENTRYPOINT ["/app/docker-entrypoint.sh"]
