#!/bin/bash
# ============================================
# Backup MongoDB (versión Docker)
# ============================================

set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="mongodb_backup_${TIMESTAMP}"

# Usar path del HOST que Docker Desktop conoce
HOST_BACKUP_PATH="/Volumes/JOAQUIN/milvus-backups/mongodb/$BACKUP_NAME"
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/mnt/qnap}"
BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/mongodb/$BACKUP_NAME"
LOG_FILE="$QNAP_MOUNT_POINT/milvus-backups/logs/mongodb_${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=================================================="
echo "   BACKUP DE MONGODB -> QNAP (Docker)"
echo "   Fecha: $(date)"
echo "=================================================="

mkdir -p "$BACKUP_PATH"
log "📁 Directorio de backup: $BACKUP_PATH"

# Volúmenes MongoDB
MONGO_VOLUMES=(
    "mongo_mongo1_data"
    "mongo_mongo2_data"
    "mongo_mongo3_data"
    "mongo_mongo4_data"
    "mongo_mongo5_data"
    "mongo_mongo6_data"
    "analiticacontainer_mongo_data"
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

log "🚀 Iniciando backup de MongoDB..."

# Backup de volúmenes
for volume in "${MONGO_VOLUMES[@]}"; do
    backup_volume "$volume"
done

# Generar metadatos
log "📝 Generando metadatos..."
cat > "$BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "$BACKUP_NAME",
    "backup_type": "mongodb",
    "backup_method": "docker",
    "parent_child_relations": {
        "pairs": [
            {"mongodb": "mongo1:27020", "milvus": "milvus-standalone-1:19530"},
            {"mongodb": "mongo2:27021", "milvus": "milvus-standalone-2:19531"},
            {"mongodb": "mongo3:27022", "milvus": "milvus-standalone-3:19532"},
            {"mongodb": "mongo4:27023", "milvus": "milvus-standalone-4:19533"},
            {"mongodb": "mongo5:27024", "milvus": "milvus-standalone-5:19534"},
            {"mongodb": "mongo6:27017", "milvus": "macrochat-milvus:19540"}
        ]
    }
}
EOF

TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log "📊 Tamaño total: $TOTAL_SIZE"

# Limpiar backups antiguos (30 días)
find "$QNAP_MOUNT_POINT/milvus-backups/mongodb" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

log "✅ Backup MongoDB completado"
