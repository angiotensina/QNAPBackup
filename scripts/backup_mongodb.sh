#!/bin/bash
# ============================================
# Backup de MongoDB con mongodump
# Mantiene integridad referencial con Milvus
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="mongodb_backup_${TIMESTAMP}"
LOG_FILE="$QNAP_MOUNT_POINT/milvus-backups/logs/mongodb_${TIMESTAMP}.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "=================================================="
echo "   BACKUP DE MONGODB -> QNAP"
echo "   Fecha: $(date)"
echo "=================================================="

# Verificar que QNAP está montado
if ! mount | grep -q "$QNAP_MOUNT_POINT"; then
    echo "❌ QNAP no está montado en $QNAP_MOUNT_POINT"
    exit 1
fi

# Crear directorio de backup
BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/mongodb/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"
log "📁 Directorio de backup: $BACKUP_PATH"

# Función para obtener puerto de MongoDB
get_mongo_port() {
    local container=$1
    case $container in
        mongo1) echo "27020" ;;
        mongo2) echo "27021" ;;
        mongo3) echo "27022" ;;
        mongo4) echo "27023" ;;
        mongo5) echo "27024" ;;
        mongo6) echo "27017" ;;
        *) echo "27017" ;;
    esac
}

# Función para obtener Milvus relacionado
get_milvus_pair() {
    local container=$1
    case $container in
        mongo1) echo "milvus-standalone-1:19530" ;;
        mongo2) echo "milvus-standalone-2:19531" ;;
        mongo3) echo "milvus-standalone-3:19532" ;;
        mongo4) echo "milvus-standalone-4:19533" ;;
        mongo5) echo "milvus-standalone-5:19534" ;;
        mongo6) echo "macrochat-milvus:19540" ;;
        *) echo "unknown" ;;
    esac
}

# Función para hacer backup de una instancia MongoDB usando mongodump en contenedor
backup_mongo_instance() {
    local container_name=$1
    local port=$(get_mongo_port "$container_name")
    local output_dir="$BACKUP_PATH/$container_name"
    
    log "🔄 Respaldando MongoDB: $container_name (puerto $port)"
    
    # Verificar que el contenedor está corriendo
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log "⚠️  Contenedor $container_name no está corriendo, saltando..."
        return 0
    fi
    
    mkdir -p "$output_dir"
    
    # Ejecutar mongodump dentro del contenedor
    if docker exec "$container_name" mongodump --out /dump --quiet 2>/dev/null; then
        # Copiar dump desde el contenedor
        docker cp "$container_name:/dump/." "$output_dir/"
        
        # Limpiar dump temporal en contenedor
        docker exec "$container_name" rm -rf /dump 2>/dev/null || true
        
        # Comprimir el backup
        log "📦 Comprimiendo $container_name..."
        tar -czf "$BACKUP_PATH/${container_name}.tar.gz" -C "$BACKUP_PATH" "$container_name"
        rm -rf "$output_dir"
        
        local size=$(du -h "$BACKUP_PATH/${container_name}.tar.gz" | cut -f1)
        log "✅ $container_name respaldado con mongodump ($size)"
    else
        log "⚠️  mongodump falló para $container_name, usando backup de volumen..."
    fi
}

# Función para backup de volumen (alternativa más rápida)
backup_mongo_volume() {
    local volume_name=$1
    local output_file="$BACKUP_PATH/${volume_name}.tar.gz"
    
    log "🔄 Respaldando volumen: $volume_name"
    
    if ! docker volume inspect "$volume_name" > /dev/null 2>&1; then
        log "⚠️  Volumen $volume_name no existe, saltando..."
        return 0
    fi
    
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

log "🚀 Iniciando backup de MongoDB..."

# Opción 1: Backup con mongodump (mantiene consistencia)
echo ""
log "📋 Método: mongodump (consistente)"
for container in $MONGO_INSTANCES; do
    backup_mongo_instance "$container"
done

# Opción 2: También hacer backup de volúmenes (más rápido para restore completo)
echo ""
log "📋 Método: Volúmenes Docker (completo)"
for volume in "${MONGO_VOLUMES[@]}"; do
    backup_mongo_volume "$volume"
done

# Generar metadatos con relación parent-child
log "📝 Generando metadatos con relación MongoDB-Milvus..."
cat > "$BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "$BACKUP_NAME",
    "backup_type": "mongodb",
    "hostname": "$(hostname)",
    "parent_child_relations": {
        "description": "MongoDB almacena documentos, Milvus almacena vectores. Deben restaurarse juntos.",
        "pairs": [
            {"mongodb": "mongo1:27020", "milvus": "milvus-standalone-1:19530", "description": "Instancia 1"},
            {"mongodb": "mongo2:27021", "milvus": "milvus-standalone-2:19531", "description": "Instancia 2"},
            {"mongodb": "mongo3:27022", "milvus": "milvus-standalone-3:19532", "description": "Instancia 3"},
            {"mongodb": "mongo4:27023", "milvus": "milvus-standalone-4:19533", "description": "Instancia 4"},
            {"mongodb": "mongo5:27024", "milvus": "milvus-standalone-5:19534", "description": "Instancia 5"},
            {"mongodb": "mongo6:27017", "milvus": "macrochat-milvus:19540", "description": "Macrochat"}
        ]
    },
    "mongodb_instances": [
        {"name": "mongo1", "port": "27020", "milvus_pair": "milvus-standalone-1:19530"},
        {"name": "mongo2", "port": "27021", "milvus_pair": "milvus-standalone-2:19531"},
        {"name": "mongo3", "port": "27022", "milvus_pair": "milvus-standalone-3:19532"},
        {"name": "mongo4", "port": "27023", "milvus_pair": "milvus-standalone-4:19533"},
        {"name": "mongo5", "port": "27024", "milvus_pair": "milvus-standalone-5:19534"},
        {"name": "mongo6", "port": "27017", "milvus_pair": "macrochat-milvus:19540"}
    ],
    "volumes": [
$(printf '        "%s",\n' "${MONGO_VOLUMES[@]}" | sed '$ s/,$//')
    ],
    "restore_order": [
        "1. Detener todos los contenedores MongoDB y Milvus relacionados",
        "2. Restaurar volúmenes de MongoDB",
        "3. Restaurar volúmenes de Milvus (del backup de Milvus)",
        "4. Iniciar MongoDB primero",
        "5. Iniciar Milvus después",
        "6. Verificar integridad de referencias"
    ]
}
EOF

# Calcular tamaño total
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log "📊 Tamaño total del backup MongoDB: $TOTAL_SIZE"

# Limpiar backups antiguos
log "🧹 Limpiando backups antiguos (más de $RETENTION_DAYS días)..."
find "$QNAP_MOUNT_POINT/milvus-backups/mongodb" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

log "✅ Backup MongoDB completado: $BACKUP_NAME"
echo ""
echo "=================================================="
echo "   BACKUP MONGODB COMPLETADO"
echo "   Ubicación: $BACKUP_PATH"
echo "   Tamaño: $TOTAL_SIZE"
echo "=================================================="
