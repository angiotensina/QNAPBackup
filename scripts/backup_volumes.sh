#!/bin/bash
# ============================================
# Backup de Volúmenes Docker de Milvus
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="milvus_backup_${TIMESTAMP}"
LOG_FILE="$QNAP_MOUNT_POINT/milvus-backups/logs/backup_${TIMESTAMP}.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=================================================="
echo "   BACKUP DE VOLÚMENES MILVUS -> QNAP"
echo "   Fecha: $(date)"
echo "=================================================="

# Verificar que QNAP está montado
if ! mount | grep -q "$QNAP_MOUNT_POINT"; then
    echo "❌ QNAP no está montado. Ejecuta primero: ./mount_qnap.sh"
    exit 1
fi

# Crear directorio de backup
BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/volumes/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"
log "📁 Directorio de backup: $BACKUP_PATH"

# Función para hacer backup de un volumen
backup_volume() {
    local volume_name=$1
    local output_file="$BACKUP_PATH/${volume_name}.tar.gz"
    
    log "🔄 Respaldando volumen: $volume_name"
    
    # Verificar que el volumen existe
    if ! docker volume inspect "$volume_name" > /dev/null 2>&1; then
        log "⚠️  Volumen $volume_name no existe, saltando..."
        return 0
    fi
    
    # Crear backup del volumen usando un contenedor temporal
    docker run --rm \
        -v "$volume_name":/source:ro \
        -v "$BACKUP_PATH":/backup \
        alpine:latest \
        tar -czf "/backup/${volume_name}.tar.gz" -C /source . 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$output_file" | cut -f1)
        log "✅ $volume_name respaldado ($size)"
    else
        log "❌ Error respaldando $volume_name"
        return 1
    fi
}

# Backup de todos los volúmenes
log "🚀 Iniciando backup de volúmenes..."

for volume in "${MILVUS_VOLUMES[@]}"; do
    backup_volume "$volume"
done

# Crear archivo de metadatos
log "📝 Generando metadatos..."
cat > "$BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "$BACKUP_NAME",
    "hostname": "$(hostname)",
    "volumes": [
$(printf '        "%s",\n' "${MILVUS_VOLUMES[@]}" | sed '$ s/,$//')
    ],
    "docker_version": "$(docker --version)",
    "milvus_containers": [
$(docker ps --format '{{.Names}}' | grep -i milvus | sed 's/^/        "/;s/$/",/' | sed '$ s/,$//')
    ]
}
EOF

# Calcular tamaño total
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log "📊 Tamaño total del backup: $TOTAL_SIZE"

# Limpiar backups antiguos
log "🧹 Limpiando backups antiguos (más de $RETENTION_DAYS días)..."
find "$QNAP_MOUNT_POINT/milvus-backups/volumes" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

log "✅ Backup completado: $BACKUP_NAME"
echo ""
echo "=================================================="
echo "   BACKUP COMPLETADO"
echo "   Ubicación: $BACKUP_PATH"
echo "   Tamaño: $TOTAL_SIZE"
echo "=================================================="
