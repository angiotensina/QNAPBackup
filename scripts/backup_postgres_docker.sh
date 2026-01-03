#!/bin/bash
# ============================================
# Backup PostgreSQL (versión Docker)
# Incluye pg_dump para cada contenedor
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env" 2>/dev/null || true

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="postgres_backup_${TIMESTAMP}"

# Usar path del HOST que Docker Desktop conoce
HOST_BACKUP_PATH="/Volumes/JOAQUIN/milvus-backups/postgres/$BACKUP_NAME"
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/Volumes/JOAQUIN}"
BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/postgres/$BACKUP_NAME"
LOG_FILE="$QNAP_MOUNT_POINT/milvus-backups/logs/postgres_${TIMESTAMP}.log"

# Configuración de contenedores PostgreSQL
# Formato: "container_name:user:database"
POSTGRES_CONTAINERS=(
    "postgres-gdash:postgres:postgres"
    "medimecum-postgres:postgres:postgres"
    "usreaderplus-db:postgres:postgres"
    "macrochat-postgres:postgres:postgres"
    "postgres_graph_clinical:postgres:postgres"
    "agents-postgres:postgres:postgres"
    "pgvector-container:postgres:postgres"
    "postgres_db1:postgres:postgres"
    "postgres_db2:postgres:postgres"
    "postgres_db3:postgres:postgres"
    "postgres_db5:postgres:postgres"
)

# Volúmenes PostgreSQL
POSTGRES_VOLUMES=(
    "agents-postgres-data"
    "analiticacontainer_postgres_data"
    "clinica-app_clinica_postgres_data"
    "graph-gpt-5_postgres_graph_clinical_data"
    "infra_postgres_data"
    "macrochat_postgres-data"
    "pgvector_data"
    "postgres_db1_data"
    "postgres_db2_data"
    "postgres_db3_data"
    "postgres_db4_data"
    "postgres_db5_data"
    "usreaderplus_postgres_data"
    "utd-exporter_postgres_data"
)

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

echo "=================================================="
echo "   BACKUP DE POSTGRESQL -> QNAP (Docker)"
echo "   Fecha: $(date)"
echo "=================================================="

mkdir -p "$BACKUP_PATH/dumps"
mkdir -p "$BACKUP_PATH/volumes"
mkdir -p "$(dirname "$LOG_FILE")"

log "📁 Directorio de backup: $BACKUP_PATH"

# ============================================
# 1. Backup con pg_dump (datos lógicos)
# ============================================
log ""
log "🗄️  FASE 1: Backup lógico con pg_dump"
log "----------------------------------------"

backup_postgres_dump() {
    local container_info=$1
    local container_name=$(echo "$container_info" | cut -d: -f1)
    local pg_user=$(echo "$container_info" | cut -d: -f2)
    local pg_database=$(echo "$container_info" | cut -d: -f3)
    
    log "🔄 Realizando pg_dump de: $container_name"
    
    # Verificar que el contenedor esté corriendo
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log "⚠️  Contenedor $container_name no está corriendo, saltando dump..."
        return 0
    fi
    
    local dump_file="$BACKUP_PATH/dumps/${container_name}_all_databases.sql.gz"
    
    # Hacer dump de TODAS las bases de datos
    if docker exec "$container_name" pg_dumpall -U "$pg_user" 2>/dev/null | gzip > "$dump_file"; then
        if [ -s "$dump_file" ]; then
            local size=$(du -h "$dump_file" | cut -f1)
            log "✅ $container_name - pg_dumpall completado ($size)"
        else
            log "⚠️  $container_name - dump vacío, intentando dump individual..."
            rm -f "$dump_file"
            
            # Intentar dump de la base de datos específica
            dump_file="$BACKUP_PATH/dumps/${container_name}_${pg_database}.sql.gz"
            if docker exec "$container_name" pg_dump -U "$pg_user" -d "$pg_database" 2>/dev/null | gzip > "$dump_file"; then
                local size=$(du -h "$dump_file" | cut -f1)
                log "✅ $container_name - pg_dump de $pg_database completado ($size)"
            else
                log "❌ Error en pg_dump de $container_name"
                rm -f "$dump_file"
            fi
        fi
    else
        log "❌ Error ejecutando pg_dumpall en $container_name"
    fi
}

# Ejecutar dumps
for container_info in "${POSTGRES_CONTAINERS[@]}"; do
    backup_postgres_dump "$container_info"
done

# ============================================
# 2. Backup de volúmenes (datos físicos)
# ============================================
log ""
log "📦 FASE 2: Backup de volúmenes Docker"
log "----------------------------------------"

backup_volume() {
    local volume_name=$1
    local output_file="$BACKUP_PATH/volumes/${volume_name}.tar.gz"
    
    log "🔄 Respaldando volumen: $volume_name"
    
    if ! docker volume inspect "$volume_name" > /dev/null 2>&1; then
        log "⚠️  Volumen $volume_name no existe, saltando..."
        return 0
    fi
    
    # Usar el path del HOST que Docker Desktop puede montar
    docker run --rm \
        -v "$volume_name":/source:ro \
        -v "$HOST_BACKUP_PATH/volumes":/backup \
        alpine:latest \
        tar -czf "/backup/${volume_name}.tar.gz" -C /source . 2>/dev/null
    
    if [ -f "$output_file" ]; then
        local size=$(du -h "$output_file" | cut -f1)
        log "✅ $volume_name respaldado ($size)"
    else
        log "❌ Error respaldando volumen $volume_name"
        return 1
    fi
}

# Backup de volúmenes
for volume in "${POSTGRES_VOLUMES[@]}"; do
    backup_volume "$volume"
done

# ============================================
# 3. Generar metadatos
# ============================================
log ""
log "📝 Generando metadatos..."

cat > "$BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "$BACKUP_NAME",
    "backup_type": "postgresql",
    "backup_method": "docker",
    "backup_components": {
        "logical_dumps": "dumps/ - pg_dumpall de cada contenedor",
        "volume_backups": "volumes/ - tar.gz de cada volumen Docker"
    },
    "containers_backed_up": [
        $(printf '"%s",' "${POSTGRES_CONTAINERS[@]}" | sed 's/,$//')
    ],
    "volumes_backed_up": [
        $(printf '"%s",' "${POSTGRES_VOLUMES[@]}" | sed 's/,$//')
    ],
    "restore_instructions": {
        "logical_restore": [
            "1. Asegurarse de que el contenedor PostgreSQL esté corriendo",
            "2. gunzip < dump.sql.gz | docker exec -i <container> psql -U postgres"
        ],
        "volume_restore": [
            "1. Detener el contenedor PostgreSQL",
            "2. docker run --rm -v <volume>:/target -v <backup_path>:/backup alpine tar -xzf /backup/<volume>.tar.gz -C /target",
            "3. Iniciar el contenedor PostgreSQL"
        ]
    }
}
EOF

# Resumen
DUMPS_SIZE=$(du -sh "$BACKUP_PATH/dumps" 2>/dev/null | cut -f1 || echo "0")
VOLUMES_SIZE=$(du -sh "$BACKUP_PATH/volumes" 2>/dev/null | cut -f1 || echo "0")
TOTAL_SIZE=$(du -sh "$BACKUP_PATH" 2>/dev/null | cut -f1 || echo "N/A")

log ""
log "=================================================="
log "   ✅ BACKUP POSTGRESQL COMPLETADO"
log "=================================================="
log ""
log "📊 Resumen:"
log "   📄 Dumps SQL:    $DUMPS_SIZE"
log "   📦 Volúmenes:    $VOLUMES_SIZE"
log "   📊 Total:        $TOTAL_SIZE"
log "   📁 Ubicación:    $BACKUP_PATH"
log ""

# Limpiar backups antiguos (30 días)
find "$QNAP_MOUNT_POINT/milvus-backups/postgres" -type d -mtime +${RETENTION_DAYS:-30} -exec rm -rf {} + 2>/dev/null || true

log "🧹 Limpieza de backups > ${RETENTION_DAYS:-30} días completada"
