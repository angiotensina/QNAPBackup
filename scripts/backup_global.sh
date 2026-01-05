#!/bin/bash
# ============================================
# BACKUP GLOBAL COMPLETO
# MongoDB + Milvus + PostgreSQL + Redis + Adicionales
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env" 2>/dev/null || true

# Configuración
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/Volumes/JOAQUIN}"
BACKUP_BASE="$QNAP_MOUNT_POINT/milvus-backups"
LOG_FILE="$BACKUP_BASE/logs/backup_global_${TIMESTAMP}.log"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de logging
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    log "${RED}❌ $1${NC}"
}

log_info() {
    log "${BLUE}📌 $1${NC}"
}

# Banner
print_banner() {
    echo ""
    echo "=================================================="
    echo "   🚀 BACKUP GLOBAL COMPLETO"
    echo "   MongoDB + Milvus + PostgreSQL + Redis"
    echo "   Fecha: $(date)"
    echo "=================================================="
    echo ""
}

# Verificar Docker
check_docker() {
    log_info "Verificando Docker..."
    if ! docker info > /dev/null 2>&1; then
        log_warning "Docker no está corriendo. Iniciando..."
        open -a Docker
        for i in {1..30}; do
            docker info > /dev/null 2>&1 && break
            sleep 2
        done
        if ! docker info > /dev/null 2>&1; then
            log_error "No se pudo iniciar Docker"
            exit 1
        fi
    fi
    log_success "Docker está activo"
}

# Verificar QNAP montado
check_qnap() {
    log_info "Verificando QNAP..."
    
    if [ ! -d "$QNAP_MOUNT_POINT" ] || [ ! -w "$QNAP_MOUNT_POINT" ]; then
        log_warning "QNAP no montado. Intentando montar..."
        
        # Intentar montar automáticamente
        if [ -f "$SCRIPT_DIR/automount_qnap.sh" ]; then
            "$SCRIPT_DIR/automount_qnap.sh" 2>/dev/null || true
        fi
        
        # Si no funciona, abrir en Finder
        if [ ! -d "$QNAP_MOUNT_POINT" ]; then
            open "smb://192.168.1.140/JOAQUIN" 2>/dev/null
            sleep 5
        fi
        
        if [ ! -d "$QNAP_MOUNT_POINT" ] || [ ! -w "$QNAP_MOUNT_POINT" ]; then
            log_error "No se pudo montar QNAP en $QNAP_MOUNT_POINT"
            echo "Por favor, monta manualmente: smb://192.168.1.140/JOAQUIN"
            exit 1
        fi
    fi
    
    # Crear estructura de directorios
    mkdir -p "$BACKUP_BASE"/{mongodb,volumes,logs,postgres}
    
    log_success "QNAP montado en $QNAP_MOUNT_POINT"
}

# Función para backup de un volumen
backup_volume() {
    local volume_name=$1
    local output_dir=$2
    local output_file="$output_dir/${volume_name}.tar.gz"
    
    if ! docker volume inspect "$volume_name" > /dev/null 2>&1; then
        log_warning "Volumen $volume_name no existe, saltando..."
        return 0
    fi
    
    docker run --rm \
        -v "$volume_name":/source:ro \
        -v "$output_dir":/backup \
        alpine:latest \
        tar -czf "/backup/${volume_name}.tar.gz" -C /source . 2>/dev/null
    
    if [ -f "$output_file" ]; then
        local size=$(du -h "$output_file" | cut -f1)
        log "   ✅ $volume_name ($size)"
        return 0
    else
        log_warning "   Error en $volume_name"
        return 1
    fi
}

# Backup de MongoDB
backup_mongodb() {
    log_info "Paso 1/4: Backup de MongoDB..."
    
    local MONGO_BACKUP_PATH="$BACKUP_BASE/mongodb/mongodb_backup_${TIMESTAMP}"
    mkdir -p "$MONGO_BACKUP_PATH"
    
    local MONGO_VOLUMES=(
        "mongo_mongo1_data"
        "mongo_mongo2_data"
        "mongo_mongo3_data"
        "mongo_mongo4_data"
        "mongo_mongo5_data"
        "mongo_mongo6_data"
        "analiticacontainer_mongo_data"
    )
    
    local success_count=0
    for vol in "${MONGO_VOLUMES[@]}"; do
        if backup_volume "$vol" "$MONGO_BACKUP_PATH"; then
            ((success_count++)) || true
        fi
    done
    
    # Metadatos
    cat > "$MONGO_BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "mongodb_backup_${TIMESTAMP}",
    "backup_type": "mongodb",
    "volumes_backed_up": $success_count
}
EOF
    
    local size=$(du -sh "$MONGO_BACKUP_PATH" | cut -f1)
    log_success "MongoDB completado: $size ($success_count volúmenes)"
}

# Backup de Milvus
backup_milvus() {
    log_info "Paso 2/4: Backup de Milvus..."
    
    local MILVUS_BACKUP_PATH="$BACKUP_BASE/volumes/milvus_backup_${TIMESTAMP}"
    mkdir -p "$MILVUS_BACKUP_PATH"
    
    local MILVUS_VOLUMES=(
        # Milvus data
        "milvus_milvus1_data"
        "milvus_milvus2_data"
        "milvus_milvus3_data"
        "milvus_milvus4_data"
        "milvus_milvus5_data"
        # Minio
        "milvus_minio1_data"
        "milvus_minio2_data"
        "milvus_minio3_data"
        "milvus_minio4_data"
        "milvus_minio5_data"
        # Etcd
        "milvus_etcd1_data"
        "milvus_etcd2_data"
        "milvus_etcd3_data"
        "milvus_etcd4_data"
        "milvus_etcd5_data"
        # Macrochat Milvus
        "macrochat_milvus-data"
        "macrochat_milvus-etcd-data"
        "macrochat_milvus-minio-data"
    )
    
    local success_count=0
    for vol in "${MILVUS_VOLUMES[@]}"; do
        if backup_volume "$vol" "$MILVUS_BACKUP_PATH"; then
            ((success_count++)) || true
        fi
    done
    
    # Metadatos
    cat > "$MILVUS_BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "milvus_backup_${TIMESTAMP}",
    "backup_type": "milvus",
    "volumes_backed_up": $success_count
}
EOF
    
    local size=$(du -sh "$MILVUS_BACKUP_PATH" | cut -f1)
    log_success "Milvus completado: $size ($success_count volúmenes)"
}

# Backup de PostgreSQL y Redis
backup_postgres_redis() {
    log_info "Paso 3/4: Backup de PostgreSQL y Redis..."
    
    local PG_BACKUP_PATH="$BACKUP_BASE/postgres/postgres_backup_${TIMESTAMP}"
    mkdir -p "$PG_BACKUP_PATH"
    
    local PG_VOLUMES=(
        "macrochat_postgres-data"
        "macrochat_redis-data"
        "macrochat_minio-data"
        "macrochat_backend-logs"
    )
    
    local success_count=0
    for vol in "${PG_VOLUMES[@]}"; do
        if backup_volume "$vol" "$PG_BACKUP_PATH"; then
            ((success_count++)) || true
        fi
    done
    
    # Metadatos
    cat > "$PG_BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "postgres_backup_${TIMESTAMP}",
    "backup_type": "postgres_redis",
    "volumes_backed_up": $success_count
}
EOF
    
    local size=$(du -sh "$PG_BACKUP_PATH" | cut -f1)
    log_success "PostgreSQL/Redis completado: $size ($success_count volúmenes)"
}

# Backup de volúmenes adicionales (otras instancias)
backup_additional() {
    log_info "Paso 4/4: Backup de volúmenes adicionales..."
    
    local ADDITIONAL_BACKUP_PATH="$BACKUP_BASE/volumes/additional_${TIMESTAMP}"
    mkdir -p "$ADDITIONAL_BACKUP_PATH"
    
    local ADDITIONAL_VOLUMES=(
        # Clinica App
        "clinica-app_etcd_data"
        "clinica-app_milvus_data"
        "clinica-app_minio_data"
        # Infra
        "infra_etcd_data"
        "infra_milvus_data"
        "infra_milvus_minio_data"
        "infra_minio_data"
        # Analitica Container
        "analiticacontainer_etcd_data"
        "analiticacontainer_milvus_data"
        "analiticacontainer_minio_data"
    )
    
    local success_count=0
    for vol in "${ADDITIONAL_VOLUMES[@]}"; do
        if backup_volume "$vol" "$ADDITIONAL_BACKUP_PATH"; then
            ((success_count++)) || true
        fi
    done
    
    # Metadatos
    cat > "$ADDITIONAL_BACKUP_PATH/metadata.json" << EOF
{
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_name": "additional_${TIMESTAMP}",
    "backup_type": "additional",
    "volumes_backed_up": $success_count
}
EOF
    
    local size=$(du -sh "$ADDITIONAL_BACKUP_PATH" | cut -f1)
    log_success "Adicionales completado: $size ($success_count volúmenes)"
}

# Generar resumen global
generate_summary() {
    log_info "Generando resumen del backup..."
    
    local SUMMARY_FILE="$BACKUP_BASE/backup_global_${TIMESTAMP}.json"
    
    # Calcular tamaños
    local mongodb_size=$(du -sh "$BACKUP_BASE/mongodb/mongodb_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo "N/A")
    local milvus_size=$(du -sh "$BACKUP_BASE/volumes/milvus_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo "N/A")
    local postgres_size=$(du -sh "$BACKUP_BASE/postgres/postgres_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo "N/A")
    local additional_size=$(du -sh "$BACKUP_BASE/volumes/additional_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo "N/A")
    local total_size=$(du -sh "$BACKUP_BASE" 2>/dev/null | cut -f1 || echo "N/A")
    
    cat > "$SUMMARY_FILE" << EOF
{
    "backup_session": "$TIMESTAMP",
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_date_local": "$(date)",
    "status": "completed",
    "components": {
        "mongodb": {
            "path": "mongodb/mongodb_backup_${TIMESTAMP}",
            "size": "$mongodb_size"
        },
        "milvus": {
            "path": "volumes/milvus_backup_${TIMESTAMP}",
            "size": "$milvus_size"
        },
        "postgres_redis": {
            "path": "postgres/postgres_backup_${TIMESTAMP}",
            "size": "$postgres_size"
        },
        "additional": {
            "path": "volumes/additional_${TIMESTAMP}",
            "size": "$additional_size"
        }
    },
    "total_backup_size": "$total_size",
    "qnap_mount_point": "$QNAP_MOUNT_POINT",
    "restore_instructions": {
        "warning": "Restaurar MongoDB y Milvus del MISMO backup para mantener consistencia",
        "steps": [
            "1. Detener todos los contenedores relacionados",
            "2. Ejecutar restore_global.sh con el TIMESTAMP del backup",
            "3. Reiniciar los contenedores"
        ]
    }
}
EOF
    
    log_success "Resumen guardado en: $SUMMARY_FILE"
}

# Limpiar backups antiguos (más de 30 días)
cleanup_old_backups() {
    log_info "Limpiando backups antiguos (>30 días)..."
    
    find "$BACKUP_BASE/mongodb" -type d -name "mongodb_backup_*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_BASE/volumes" -type d -name "milvus_backup_*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_BASE/volumes" -type d -name "additional_*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_BASE/postgres" -type d -name "postgres_backup_*" -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_BASE/logs" -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true
    find "$BACKUP_BASE" -type f -name "backup_global_*.json" -mtime +30 -delete 2>/dev/null || true
    
    log_success "Limpieza completada"
}

# Imprimir resumen final
print_summary() {
    echo ""
    echo "=================================================="
    echo "   📊 RESUMEN DEL BACKUP"
    echo "=================================================="
    echo ""
    echo "   Timestamp: $TIMESTAMP"
    echo "   Destino:   $QNAP_MOUNT_POINT/milvus-backups/"
    echo ""
    echo "   📁 MongoDB:       $(du -sh "$BACKUP_BASE/mongodb/mongodb_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "   📁 Milvus:        $(du -sh "$BACKUP_BASE/volumes/milvus_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "   📁 PostgreSQL:    $(du -sh "$BACKUP_BASE/postgres/postgres_backup_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "   📁 Adicionales:   $(du -sh "$BACKUP_BASE/volumes/additional_${TIMESTAMP}" 2>/dev/null | cut -f1 || echo 'N/A')"
    echo ""
    echo "   📦 Total Backup:  $(du -sh "$BACKUP_BASE" 2>/dev/null | cut -f1 || echo 'N/A')"
    echo ""
    echo "   📝 Log: $LOG_FILE"
    echo ""
    echo "=================================================="
    echo "   ✅ BACKUP GLOBAL COMPLETADO"
    echo "   $(date)"
    echo "=================================================="
}

# ============================================
# MAIN
# ============================================
main() {
    print_banner
    
    # Verificaciones
    check_docker
    check_qnap
    
    echo ""
    
    # Ejecutar backups
    backup_mongodb
    echo ""
    
    backup_milvus
    echo ""
    
    backup_postgres_redis
    echo ""
    
    backup_additional
    echo ""
    
    # Generar resumen y limpiar
    generate_summary
    cleanup_old_backups
    
    # Mostrar resumen final
    print_summary
}

# Ejecutar
main "$@"
