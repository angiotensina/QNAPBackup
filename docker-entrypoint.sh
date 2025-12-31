#!/bin/bash
# ============================================
# Docker Entrypoint para Backup Milvus/MongoDB
# ============================================

set -e

echo "=================================================="
echo "   🐳 MILVUS/MONGODB BACKUP SERVICE"
echo "   Iniciado: $(date)"
echo "=================================================="

# Cargar configuración
source /app/config.env

# Sobrescribir con variables de entorno si existen (Docker tiene prioridad)
QNAP_HOST="${QNAP_HOST:-192.168.1.140}"
QNAP_SHARE="${QNAP_SHARE:-JOAQUIN}"
QNAP_USER="${QNAP_USER:-admin}"
QNAP_PASSWORD="${QNAP_PASSWORD:-}"
# En Docker, el mount point es /mnt/qnap (volumen montado desde host)
QNAP_MOUNT_POINT="/mnt/qnap"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * 0}"

# Exportar para scripts hijos
export QNAP_MOUNT_POINT

echo "📋 Configuración:"
echo "   QNAP Host: $QNAP_HOST"
echo "   QNAP Share: $QNAP_SHARE"
echo "   QNAP User: $QNAP_USER"
echo "   Mount Point: $QNAP_MOUNT_POINT"
echo "   Schedule: $BACKUP_SCHEDULE"
echo ""

# Función para montar QNAP
mount_qnap() {
    echo "🔌 Verificando acceso a QNAP..."
    
    # En Docker, usamos el volumen montado desde el host
    if [ -d "$QNAP_MOUNT_POINT" ] && [ -w "$QNAP_MOUNT_POINT" ]; then
        echo "✅ QNAP accesible en $QNAP_MOUNT_POINT"
        mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/mongodb"
        mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/volumes"
        mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/logs"
        return 0
    fi
    
    echo "❌ QNAP no accesible en $QNAP_MOUNT_POINT"
    echo "   Asegúrate de que el volumen está montado en el host"
    return 1
}

# Función de backup
run_backup() {
    echo ""
    echo "=================================================="
    echo "   🚀 EJECUTANDO BACKUP"
    echo "   Fecha: $(date)"
    echo "=================================================="
    
    # Montar si no está montado
    mount_qnap || return 1
    
    # Actualizar config.env con mount point correcto
    export QNAP_MOUNT_POINT="$QNAP_MOUNT_POINT"
    
    # Ejecutar backup de MongoDB
    echo ""
    echo "📦 Backup MongoDB..."
    /app/scripts/backup_mongodb_docker.sh || echo "⚠️ Error en backup MongoDB"
    
    # Ejecutar backup de Milvus
    echo ""
    echo "📦 Backup Milvus..."
    /app/scripts/backup_volumes_docker.sh || echo "⚠️ Error en backup Milvus"
    
    echo ""
    echo "✅ Backup completado: $(date)"
}

# Modo de ejecución
case "${1:-scheduler}" in
    "backup")
        # Ejecutar backup una vez y salir
        run_backup
        ;;
    "scheduler"|*)
        # Modo scheduler: ejecutar según cron
        echo "⏰ Modo scheduler activado"
        echo "   Próximo backup según schedule: $BACKUP_SCHEDULE"
        echo ""
        
        # Ejecutar backup inicial si se solicita
        if [ "${RUN_ON_START:-false}" = "true" ]; then
            echo "🔄 Ejecutando backup inicial..."
            run_backup
        fi
        
        # Crear crontab
        echo "$BACKUP_SCHEDULE /app/run_backup.sh >> /app/logs/backup.log 2>&1" > /etc/crontabs/root
        
        # Crear script wrapper para cron
        cat > /app/run_backup.sh << 'EOFSCRIPT'
#!/bin/bash
source /app/config.env
export QNAP_HOST="${QNAP_HOST}"
export QNAP_SHARE="${QNAP_SHARE}"
export QNAP_USER="${QNAP_USER}"
export QNAP_PASSWORD="${QNAP_PASSWORD}"
export QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/mnt/qnap}"

# Montar QNAP
mkdir -p "$QNAP_MOUNT_POINT"
mount -t cifs "//${QNAP_HOST}/${QNAP_SHARE}" "$QNAP_MOUNT_POINT" \
    -o "username=${QNAP_USER},password=${QNAP_PASSWORD},vers=3.0" 2>/dev/null || true

# Ejecutar backups
/app/scripts/backup_mongodb_docker.sh
/app/scripts/backup_volumes_docker.sh

echo "Backup completado: $(date)"
EOFSCRIPT
        chmod +x /app/run_backup.sh
        
        # Iniciar cron en foreground
        echo "🕐 Iniciando scheduler..."
        crond -f -l 2
        ;;
esac
