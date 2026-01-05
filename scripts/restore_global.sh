#!/bin/bash
# ============================================
# RESTAURACIÓN GLOBAL COMPLETA
# MongoDB + Milvus + PostgreSQL + Redis + Adicionales
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env" 2>/dev/null || true

# Configuración
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/Volumes/JOAQUIN}"
BACKUP_BASE="$QNAP_MOUNT_POINT/milvus-backups"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }
log_info() { log "${BLUE}📌 $1${NC}"; }

# Banner
print_banner() {
    echo ""
    echo "=================================================="
    echo "   🔄 RESTAURACIÓN GLOBAL"
    echo "   MongoDB + Milvus + PostgreSQL + Redis"
    echo "   Fecha: $(date)"
    echo "=================================================="
    echo ""
}

# Listar backups disponibles
list_backups() {
    echo "📋 Backups disponibles:"
    echo ""
    
    if [ -d "$BACKUP_BASE" ]; then
        ls -1 "$BACKUP_BASE" | grep "backup_global_.*\.json" | sed 's/backup_global_//g' | sed 's/\.json//g' | sort -r | head -10
    else
        echo "No se encontraron backups en $BACKUP_BASE"
    fi
    echo ""
}

# Restaurar un volumen
restore_volume() {
    local volume_name=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        log_warning "Archivo no encontrado: $backup_file"
        return 1
    fi
    
    # Crear volumen si no existe
    docker volume create "$volume_name" > /dev/null 2>&1 || true
    
    # Restaurar
    docker run --rm \
        -v "$volume_name":/target \
        -v "$(dirname "$backup_file")":/backup:ro \
        alpine:latest \
        sh -c "rm -rf /target/* && tar -xzf /backup/$(basename "$backup_file") -C /target" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "   ✅ $volume_name restaurado"
        return 0
    else
        log_warning "   Error restaurando $volume_name"
        return 1
    fi
}

# Restaurar MongoDB
restore_mongodb() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/mongodb/mongodb_backup_${timestamp}"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de MongoDB para $timestamp"
        return 1
    fi
    
    log_info "Restaurando MongoDB..."
    
    for tar_file in "$backup_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
        fi
    done
    
    log_success "MongoDB restaurado"
}

# Restaurar Milvus
restore_milvus() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/volumes/milvus_backup_${timestamp}"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de Milvus para $timestamp"
        return 1
    fi
    
    log_info "Restaurando Milvus..."
    
    for tar_file in "$backup_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
        fi
    done
    
    log_success "Milvus restaurado"
}

# Restaurar PostgreSQL/Redis
restore_postgres() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/postgres/postgres_backup_${timestamp}"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de PostgreSQL para $timestamp"
        return 1
    fi
    
    log_info "Restaurando PostgreSQL/Redis..."
    
    # Detectar si los backups están en subdirectorio volumes/ (nuevo formato)
    local volumes_path="$backup_path"
    if [ -d "$backup_path/volumes" ]; then
        volumes_path="$backup_path/volumes"
        log_info "Detectado formato nuevo (subdirectorio volumes/)"
    fi
    
    local restored_count=0
    for tar_file in "$volumes_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
            ((restored_count++))
        fi
    done
    
    if [ $restored_count -eq 0 ]; then
        log_warning "No se encontraron archivos .tar.gz para restaurar"
        return 1
    fi
    
    log_success "PostgreSQL/Redis restaurado ($restored_count volúmenes)"
}

# Restaurar adicionales
restore_additional() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/volumes/additional_${timestamp}"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup adicional para $timestamp"
        return 1
    fi
    
    log_info "Restaurando volúmenes adicionales..."
    
    for tar_file in "$backup_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
        fi
    done
    
    log_success "Adicionales restaurados"
}

# Función principal de restauración
restore_all() {
    local timestamp=$1
    
    if [ -z "$timestamp" ]; then
        log_error "Debes especificar un timestamp de backup"
        echo ""
        list_backups
        echo "Uso: $0 <TIMESTAMP>"
        echo "Ejemplo: $0 20260105_131322"
        exit 1
    fi
    
    # Verificar que existe el backup
    if [ ! -f "$BACKUP_BASE/backup_global_${timestamp}.json" ]; then
        # Buscar el backup más cercano
        log_warning "No se encontró backup_global_${timestamp}.json"
        echo "Buscando componentes individuales..."
    fi
    
    echo ""
    echo "⚠️  ADVERTENCIA: Esta operación sobrescribirá los datos actuales."
    echo "   Timestamp: $timestamp"
    echo ""
    read -p "¿Deseas continuar? (s/N): " confirm
    
    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        echo "Operación cancelada."
        exit 0
    fi
    
    echo ""
    log_info "Iniciando restauración..."
    echo ""
    
    # Detener contenedores relacionados
    log_info "Se recomienda detener los contenedores antes de restaurar."
    echo "Contenedores sugeridos a detener:"
    echo "  - mongo1, mongo2, mongo3, mongo4, mongo5, mongo6"
    echo "  - milvus-standalone-1/2/3/4/5"
    echo "  - macrochat containers"
    echo ""
    read -p "¿Has detenido los contenedores? (s/N): " stopped
    
    if [[ ! "$stopped" =~ ^[sS]$ ]]; then
        log_warning "Se recomienda detener los contenedores primero"
    fi
    
    echo ""
    
    # Restaurar componentes
    restore_mongodb "$timestamp"
    restore_milvus "$timestamp"
    restore_postgres "$timestamp"
    restore_additional "$timestamp"
    
    echo ""
    echo "=================================================="
    echo "   ✅ RESTAURACIÓN COMPLETADA"
    echo "   Timestamp: $timestamp"
    echo "   $(date)"
    echo "=================================================="
    echo ""
    echo "📌 Próximos pasos:"
    echo "   1. Reinicia los contenedores"
    echo "   2. Verifica que los datos estén correctos"
}

# ============================================
# MAIN
# ============================================
print_banner

case "${1:-}" in
    list|--list|-l)
        list_backups
        ;;
    help|--help|-h)
        echo "Uso: $0 [comando|timestamp]"
        echo ""
        echo "Comandos:"
        echo "  list    - Listar backups disponibles"
        echo "  help    - Mostrar esta ayuda"
        echo ""
        echo "Restaurar:"
        echo "  $0 <TIMESTAMP>  - Restaurar backup específico"
        echo ""
        echo "Ejemplos:"
        echo "  $0 list"
        echo "  $0 20260105_131322"
        ;;
    *)
        if [ -n "$1" ]; then
            restore_all "$1"
        else
            list_backups
            echo "Uso: $0 <TIMESTAMP>"
        fi
        ;;
esac
