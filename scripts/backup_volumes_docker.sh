#!/bin/bash
# ============================================
# Backup Milvus Volumes (versión Docker)
# ============================================

set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="milvus_backup_${TIMESTAMP}"

# Usar path del HOST que Docker Desktop conoce
HOST_BACKUP_PATH="/Volumes/JOAQUIN/milvus-backups/volumes/$BACKUP_NAME"
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/mnt/qnap}"
BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/volumes/$BACKUP_NAME"
LOG_FILE="$QNAP_MOUNT_POINT/milvus-backups/logs/milvus_${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=================================================="
echo "   BACKUP DE MILVUS -> QNAP (Docker)"
echo "   Fecha: $(date)"
echo "=================================================="

mkdir -p "$BACKUP_PATH"
log "📁 Directorio de backup: $BACKUP_PATH"

# Volúmenes Milvus
MILVUS_VOLUMES=(
    "milvus_milvus1_data"
    "milvus_milvus2_data"
    "milvus_milvus3_data"
    "milvus_milvus4_data"
    "milvus_milvus5_data"
    "milvus_minio1_data"
    "milvus_minio2_data"
    "milvus_minio3_data"
    "milvus_minio4_data"
    "milvus_minio5_data"
    "milvus_etcd1_data"
    "milvus_etcd2_data"
    "milvus_etcd3_data"
    "milvus_etcd4_data"
    "milvus_etcd5_data"
    "macrochat_milvus-data"
    "macrochat_milvus-etcd-data"
    "macrochat_milvus-minio-data"
)

# Función para backup de volumen
backup_volume() {
    local volume_name=$1
    local output_file="$BACKUP_PATH/${volume_name}.tar.gz"
    
    log "🔄 Respaldando volumen: $volume_name"
    
    if ! docker volume inspect "$volume_name" > /dev/null 2>&1; then
        log "⚠️  Volumen $volume_name no existe, saltando..."
        return 0
    fi
    
    # Usar el path del HOST que Docker Desktop puede montar
    docker run --rm \
        -v "$volume_name":/source:ro \
        -v "$HOST_BACKUP_PATH":/backup \
        alpine:latest \
        tar -czf "/backup/${volume_name}.tar.gz" -C /source . 2>/dev/null
    
    if [ -f "$output_file" ]; then
        local size=$(du -h "$output_file" | cut -f1)
        log "✅ $volume_name respaldado ($size)"
    else
        log "❌ Error respaldando $volume_name"
        return 1
    fi
}

log "🚀 Iniciando backup de Milvus..."

# Backup de volúmenes
for volume in "${MILVUS_VOLUMES[@]}"; do
    backup_volume "$volume"
done

# Generar metadatos
log "📝 Generando metadatos..."
cat > "$BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "$BACKUP_NAME",
    "backup_type": "milvus",
    "backup_method": "docker",
    "milvus_instances": [
        {"name": "milvus-standalone-1", "port": 19530},
        {"name": "milvus-standalone-2", "port": 19531},
        {"name": "milvus-standalone-3", "port": 19532},
        {"name": "milvus-standalone-4", "port": 19533},
        {"name": "milvus-standalone-5", "port": 19534},
        {"name": "macrochat-milvus", "port": 19540}
    ]
}
EOF

TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log "📊 Tamaño total: $TOTAL_SIZE"

# Limpiar backups antiguos (30 días)
find "$QNAP_MOUNT_POINT/milvus-backups/volumes" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

log "✅ Backup Milvus completado"
