#!/bin/bash
# ============================================
# RESTAURACIÓN COMPLETA DE TODAS LAS BASES DE DATOS
# MongoDB + Milvus + PostgreSQL + Redis
# ============================================
# Este script restaura todos los volúmenes Docker
# desde los backups almacenados en QNAP
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env" 2>/dev/null || true

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuración
QNAP_MOUNT_POINT="${QNAP_MOUNT_POINT:-/Volumes/JOAQUIN}"
BACKUP_BASE="$QNAP_MOUNT_POINT/milvus-backups"

# Rutas a los docker-compose de las bases de datos
DBMAKER_PATH="${DBMAKER_PATH:-/Users/joaquinchamorromohedas/Desktop/QNAPBackup/CONSTRUCCION BDS/DBMakerOK}"
MONGO_COMPOSE_PATH="$DBMAKER_PATH/mongo"
POSTGRES_COMPOSE_PATH="$DBMAKER_PATH/postgres"
MILVUS_COMPOSE_PATH="$DBMAKER_PATH/milvus"

# Contadores
RESTORED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Logging
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error() { log "${RED}❌ $1${NC}"; }
log_info() { log "${BLUE}📌 $1${NC}"; }
log_header() { echo -e "\n${CYAN}$1${NC}"; }

# Banner
print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🔄 RESTAURACIÓN COMPLETA DE BASES DE DATOS            ║${NC}"
    echo -e "${CYAN}║         MongoDB + Milvus + PostgreSQL                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "   📅 Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "   📁 Fuente: $BACKUP_BASE"
    echo ""
}

# Verificar QNAP montado
check_qnap() {
    log_info "Verificando conexión a QNAP..."
    
    if [ ! -d "$QNAP_MOUNT_POINT" ] || ! mount | grep -q "JOAQUIN\|$QNAP_MOUNT_POINT"; then
        log_warning "QNAP no está montado"
        echo ""
        echo "Intentando montar QNAP..."
        open "smb://192.168.1.140/JOAQUIN" 2>/dev/null || true
        
        echo ""
        echo -e "${YELLOW}Por favor, monta el QNAP manualmente si no se abre automáticamente:${NC}"
        echo "   1. Finder -> Ir -> Conectar al servidor (⌘K)"
        echo "   2. Escribir: smb://192.168.1.140/JOAQUIN"
        echo "   3. Introducir credenciales"
        echo ""
        read -p "Presiona ENTER cuando el QNAP esté montado... "
        
        # Verificar de nuevo
        if [ ! -d "$QNAP_MOUNT_POINT/milvus-backups" ]; then
            log_error "No se pudo acceder a los backups en QNAP"
            echo "Verifica que el share esté montado en /Volumes/JOAQUIN"
            exit 1
        fi
    fi
    
    log_success "QNAP accesible"
}

# Listar backups disponibles
list_available_backups() {
    echo ""
    log_header "📋 BACKUPS DISPONIBLES"
    echo "───────────────────────────────────────────────────────────"
    
    local has_backups=false
    
    # Buscar backups globales
    if ls "$BACKUP_BASE"/backup_full_*.json 2>/dev/null | head -1 > /dev/null; then
        echo ""
        echo -e "${GREEN}🔹 Backups Completos (Full):${NC}"
        for f in $(ls -1t "$BACKUP_BASE"/backup_full_*.json 2>/dev/null | head -5); do
            local ts=$(basename "$f" | sed 's/backup_full_//' | sed 's/.json//')
            local date_fmt=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            echo "   • $ts  ($date_fmt)"
        done
        has_backups=true
    fi
    
    # Estructura de BDs
    if [ -d "$BACKUP_BASE/structure" ] && ls "$BACKUP_BASE/structure"/dbmaker_* 2>/dev/null | head -1 > /dev/null; then
        echo ""
        echo -e "${GREEN}🏗️  Estructura (docker-compose):${NC}"
        for d in $(ls -1d "$BACKUP_BASE/structure"/dbmaker_* 2>/dev/null | sort -r | head -5); do
            local ts=$(basename "$d" | sed 's/dbmaker_//')
            local date_fmt=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            local size=$(du -sh "$d" 2>/dev/null | cut -f1)
            echo "   • $ts  ($date_fmt) - $size"
        done
        has_backups=true
    fi
    
    # MongoDB
    if [ -d "$BACKUP_BASE/mongodb" ] && ls "$BACKUP_BASE/mongodb"/mongodb_backup_* 2>/dev/null | head -1 > /dev/null; then
        echo ""
        echo -e "${GREEN}🍃 MongoDB:${NC}"
        for d in $(ls -1d "$BACKUP_BASE/mongodb"/mongodb_backup_* 2>/dev/null | sort -r | head -5); do
            local ts=$(basename "$d" | sed 's/mongodb_backup_//')
            local date_fmt=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            local size=$(du -sh "$d" 2>/dev/null | cut -f1)
            echo "   • $ts  ($date_fmt) - $size"
        done
        has_backups=true
    fi
    
    # Milvus
    if [ -d "$BACKUP_BASE/volumes" ] && ls "$BACKUP_BASE/volumes"/milvus_backup_* 2>/dev/null | head -1 > /dev/null; then
        echo ""
        echo -e "${GREEN}🔷 Milvus:${NC}"
        for d in $(ls -1d "$BACKUP_BASE/volumes"/milvus_backup_* 2>/dev/null | sort -r | head -5); do
            local ts=$(basename "$d" | sed 's/milvus_backup_//')
            local date_fmt=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            local size=$(du -sh "$d" 2>/dev/null | cut -f1)
            echo "   • $ts  ($date_fmt) - $size"
        done
        has_backups=true
    fi
    
    # PostgreSQL
    if [ -d "$BACKUP_BASE/postgres" ] && ls "$BACKUP_BASE/postgres"/postgres_backup_* 2>/dev/null | head -1 > /dev/null; then
        echo ""
        echo -e "${GREEN}🐘 PostgreSQL:${NC}"
        for d in $(ls -1d "$BACKUP_BASE/postgres"/postgres_backup_* 2>/dev/null | sort -r | head -5); do
            local ts=$(basename "$d" | sed 's/postgres_backup_//')
            local date_fmt=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            local size=$(du -sh "$d" 2>/dev/null | cut -f1)
            echo "   • $ts  ($date_fmt) - $size"
        done
        has_backups=true
    fi
    
    if [ "$has_backups" = false ]; then
        log_warning "No se encontraron backups"
        exit 1
    fi
    
    echo ""
    echo "───────────────────────────────────────────────────────────"
}

# Restaurar un volumen Docker
restore_volume() {
    local volume_name=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        log_warning "Archivo no encontrado: $backup_file"
        ((SKIPPED_COUNT++))
        return 1
    fi
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    log "   🔄 Restaurando: $volume_name ($file_size)"
    
    # Crear volumen si no existe
    docker volume create "$volume_name" > /dev/null 2>&1 || true
    
    # Restaurar usando alpine
    if docker run --rm \
        -v "$volume_name":/target \
        -v "$(dirname "$backup_file")":/backup:ro \
        alpine:latest \
        sh -c "rm -rf /target/* 2>/dev/null; tar -xzf /backup/$(basename "$backup_file") -C /target" 2>/dev/null; then
        log_success "   $volume_name restaurado"
        ((RESTORED_COUNT++))
        return 0
    else
        log_error "   Error restaurando $volume_name"
        ((FAILED_COUNT++))
        return 1
    fi
}

# Restaurar estructura de bases de datos (docker-compose, .env)
restore_structure() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/structure/dbmaker_${timestamp}"
    
    log_header "🏗️  RESTAURANDO ESTRUCTURA DE BASES DE DATOS"
    echo "───────────────────────────────────────────────────────────"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de estructura en: $backup_path"
        log_info "Usando estructura existente en: $DBMAKER_PATH"
        return 1
    fi
    
    log_info "Origen: $backup_path"
    log_info "Destino: $DBMAKER_PATH"
    
    echo ""
    read -p "   ¿Restaurar estructura a $DBMAKER_PATH? (s/N): " confirm_structure
    
    if [[ "$confirm_structure" =~ ^[sS]$ ]]; then
        # Hacer backup de la estructura actual si existe
        if [ -d "$DBMAKER_PATH" ]; then
            local backup_current="${DBMAKER_PATH}_backup_$(date +%Y%m%d_%H%M%S)"
            log_info "Guardando estructura actual en: $backup_current"
            mv "$DBMAKER_PATH" "$backup_current" 2>/dev/null || true
        fi
        
        # Copiar estructura desde backup
        mkdir -p "$DBMAKER_PATH"
        cp -R "$backup_path"/* "$DBMAKER_PATH/" 2>/dev/null && {
            log_success "Estructura restaurada correctamente"
            echo ""
            log_info "Contenido restaurado:"
            ls -la "$DBMAKER_PATH" | head -10
        } || {
            log_error "Error restaurando estructura"
            # Intentar restaurar backup anterior
            if [ -d "$backup_current" ]; then
                mv "$backup_current" "$DBMAKER_PATH" 2>/dev/null
            fi
            return 1
        }
    else
        log_info "Usando estructura existente"
    fi
    
    return 0
}

# Restaurar MongoDB
restore_mongodb() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/mongodb/mongodb_backup_${timestamp}"
    
    log_header "🍃 RESTAURANDO MONGODB"
    echo "───────────────────────────────────────────────────────────"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de MongoDB en: $backup_path"
        return 1
    fi
    
    log_info "Directorio: $backup_path"
    
    local count=0
    for tar_file in "$backup_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        log_warning "No se encontraron archivos .tar.gz en el backup"
    else
        log_success "MongoDB: $count volúmenes procesados"
    fi
}

# Restaurar Milvus
restore_milvus() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/volumes/milvus_backup_${timestamp}"
    
    log_header "🔷 RESTAURANDO MILVUS"
    echo "───────────────────────────────────────────────────────────"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de Milvus en: $backup_path"
        return 1
    fi
    
    log_info "Directorio: $backup_path"
    
    local count=0
    for tar_file in "$backup_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        log_warning "No se encontraron archivos .tar.gz en el backup"
    else
        log_success "Milvus: $count volúmenes procesados"
    fi
}

# Restaurar PostgreSQL
restore_postgresql() {
    local timestamp=$1
    local backup_path="$BACKUP_BASE/postgres/postgres_backup_${timestamp}"
    
    log_header "🐘 RESTAURANDO POSTGRESQL"
    echo "───────────────────────────────────────────────────────────"
    
    if [ ! -d "$backup_path" ]; then
        log_warning "No se encontró backup de PostgreSQL en: $backup_path"
        return 1
    fi
    
    log_info "Directorio: $backup_path"
    
    # Detectar si los backups están en subdirectorio volumes/ (nuevo formato)
    local volumes_path="$backup_path"
    if [ -d "$backup_path/volumes" ]; then
        volumes_path="$backup_path/volumes"
        log_info "Usando formato nuevo (subdirectorio volumes/)"
    fi
    
    local count=0
    for tar_file in "$volumes_path"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local vol_name=$(basename "$tar_file" .tar.gz)
            restore_volume "$vol_name" "$tar_file"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        log_warning "No se encontraron archivos .tar.gz en el backup de volúmenes"
    else
        log_success "PostgreSQL: $count volúmenes procesados"
    fi
    
    # Verificar si hay dumps SQL
    if [ -d "$backup_path/dumps" ]; then
        local dump_count=$(ls -1 "$backup_path/dumps"/*.sql.gz 2>/dev/null | wc -l)
        if [ "$dump_count" -gt 0 ]; then
            echo ""
            log_info "Dumps SQL disponibles para restauración manual:"
            for dump in "$backup_path/dumps"/*.sql.gz; do
                if [ -f "$dump" ]; then
                    local size=$(du -h "$dump" | cut -f1)
                    echo "   📄 $(basename "$dump") ($size)"
                fi
            done
            echo ""
            log_info "Para restaurar dumps SQL manualmente:"
            echo "   gunzip -c <archivo.sql.gz> | docker exec -i <container> psql -U postgres"
        fi
    fi
}

# Detener contenedores
stop_containers() {
    log_header "⏹️  DETENIENDO CONTENEDORES"
    echo "───────────────────────────────────────────────────────────"
    
    # MongoDB - usar docker-compose si existe
    log_info "Deteniendo MongoDB..."
    if [ -f "$MONGO_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$MONGO_COMPOSE_PATH" && docker compose down 2>/dev/null) && log "   ⏸️  MongoDB (compose) detenido" || true
    else
        for instance in mongo1 mongo2 mongo3 mongo4 mongo5 mongo6; do
            docker stop "$instance" 2>/dev/null && log "   ⏸️  $instance detenido" || true
        done
    fi
    
    # PostgreSQL - usar docker-compose si existe
    log_info "Deteniendo PostgreSQL..."
    if [ -f "$POSTGRES_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$POSTGRES_COMPOSE_PATH" && docker compose down 2>/dev/null) && log "   ⏸️  PostgreSQL (compose) detenido" || true
    else
        local postgres_containers=$(docker ps --format "{{.Names}}" | grep -iE "postgres|pgvector" || true)
        for container in $postgres_containers; do
            docker stop "$container" 2>/dev/null && log "   ⏸️  $container detenido" || true
        done
    fi
    
    # Milvus - usar docker-compose si existe
    log_info "Deteniendo Milvus..."
    if [ -f "$MILVUS_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$MILVUS_COMPOSE_PATH" && docker compose down 2>/dev/null) && log "   ⏸️  Milvus (compose) detenido" || true
    else
        for instance in milvus-standalone-1 milvus-standalone-2 milvus-standalone-3 milvus-standalone-4 milvus-standalone-5 macrochat-milvus milvus-standalone; do
            docker stop "$instance" 2>/dev/null && log "   ⏸️  $instance detenido" || true
        done
        # Dependencias de Milvus (etcd, minio)
        for prefix in milvus macrochat; do
            for service in etcd minio; do
                docker stop "${prefix}-${service}" 2>/dev/null && log "   ⏸️  ${prefix}-${service} detenido" || true
            done
        done
    fi
    
    log_success "Contenedores detenidos"
    sleep 2
}

# Iniciar contenedores
start_containers() {
    log_header "▶️  INICIANDO CONTENEDORES"
    echo "───────────────────────────────────────────────────────────"
    
    # Iniciar MongoDB primero (Parent) - usar docker-compose si existe
    log_info "Iniciando MongoDB (Parent)..."
    if [ -f "$MONGO_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$MONGO_COMPOSE_PATH" && docker compose up -d 2>/dev/null) && log_success "MongoDB (compose) iniciado" || log_warning "Error iniciando MongoDB"
    else
        for instance in mongo1 mongo2 mongo3 mongo4 mongo5 mongo6; do
            docker start "$instance" 2>/dev/null && log "   ▶️  $instance iniciado" || true
        done
    fi
    
    log "⏳ Esperando que MongoDB esté listo (10s)..."
    sleep 10
    
    # Iniciar Milvus - usar docker-compose si existe
    log_info "Iniciando Milvus..."
    if [ -f "$MILVUS_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$MILVUS_COMPOSE_PATH" && docker compose up -d 2>/dev/null) && log_success "Milvus (compose) iniciado" || log_warning "Error iniciando Milvus"
    else
        # Iniciar dependencias de Milvus
        log_info "Iniciando dependencias de Milvus (etcd, minio)..."
        for prefix in milvus macrochat; do
            for service in etcd minio; do
                docker start "${prefix}-${service}" 2>/dev/null && log "   ▶️  ${prefix}-${service} iniciado" || true
            done
        done
        sleep 5
        # Iniciar Milvus (Child)
        for instance in milvus-standalone-1 milvus-standalone-2 milvus-standalone-3 milvus-standalone-4 milvus-standalone-5 macrochat-milvus milvus-standalone; do
            docker start "$instance" 2>/dev/null && log "   ▶️  $instance iniciado" || true
        done
    fi
    
    sleep 5
    
    # Iniciar PostgreSQL - usar docker-compose si existe
    log_info "Iniciando PostgreSQL..."
    if [ -f "$POSTGRES_COMPOSE_PATH/docker-compose.yml" ]; then
        (cd "$POSTGRES_COMPOSE_PATH" && docker compose up -d 2>/dev/null) && log_success "PostgreSQL (compose) iniciado" || log_warning "Error iniciando PostgreSQL"
    else
        local postgres_containers=$(docker ps -a --format "{{.Names}}" | grep -iE "postgres|pgvector" || true)
        for container in $postgres_containers; do
            docker start "$container" 2>/dev/null && log "   ▶️  $container iniciado" || true
        done
    fi
    
    log_success "Contenedores iniciados"
}

# Verificar estado
verify_status() {
    log_header "🔍 VERIFICANDO ESTADO"
    echo "───────────────────────────────────────────────────────────"
    
    echo ""
    echo "MongoDB:"
    docker ps --format "   {{.Names}}: {{.Status}}" | grep -i mongo || echo "   (ninguno corriendo)"
    
    echo ""
    echo "Milvus:"
    docker ps --format "   {{.Names}}: {{.Status}}" | grep -i milvus || echo "   (ninguno corriendo)"
    
    echo ""
    echo "PostgreSQL:"
    docker ps --format "   {{.Names}}: {{.Status}}" | grep -iE "postgres|pgvector" || echo "   (ninguno corriendo)"
}

# Restauración completa
restore_all() {
    local timestamp=$1
    
    echo ""
    log_header "⚠️  ADVERTENCIA IMPORTANTE"
    echo "───────────────────────────────────────────────────────────"
    echo "   Esta operación:"
    echo "   • Detendrá TODOS los contenedores de bases de datos"
    echo "   • Sobrescribirá TODOS los datos actuales"
    echo "   • Restaurará desde timestamp: $timestamp"
    echo ""
    
    read -p "   ¿Continuar? (escribe 'RESTAURAR' para confirmar): " confirm
    
    if [ "$confirm" != "RESTAURAR" ]; then
        log_warning "Operación cancelada"
        exit 0
    fi
    
    echo ""
    
    # 1. Detener contenedores
    stop_containers
    
    # 2. Restaurar datos
    restore_mongodb "$timestamp"
    restore_milvus "$timestamp"
    restore_postgresql "$timestamp"
    
    # 3. Iniciar contenedores
    start_containers
    
    sleep 5
    
    # 4. Verificar estado
    verify_status
    
    # Resumen final
    echo ""
    log_header "📊 RESUMEN DE RESTAURACIÓN"
    echo "═══════════════════════════════════════════════════════════"
    echo -e "   ${GREEN}✅ Restaurados: $RESTORED_COUNT volúmenes${NC}"
    echo -e "   ${YELLOW}⏭️  Saltados:    $SKIPPED_COUNT volúmenes${NC}"
    echo -e "   ${RED}❌ Fallidos:    $FAILED_COUNT volúmenes${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    log_info "Próximos pasos recomendados:"
    echo "   1. Verificar que los contenedores estén 'healthy'"
    echo "   2. Probar la conexión a cada base de datos"
    echo "   3. Verificar la integridad de los datos"
    echo ""
}

# Seleccionar timestamp interactivamente
select_timestamp() {
    list_available_backups
    
    echo ""
    read -p "Introduce el timestamp a restaurar (ej: 20260105_131322): " selected_ts
    
    if [ -z "$selected_ts" ]; then
        log_error "No se especificó timestamp"
        exit 1
    fi
    
    echo "$selected_ts"
}

# Restauración con timestamps específicos para cada base de datos
restore_with_specific_timestamps() {
    echo ""
    list_available_backups
    
    log_header "🔧 CONFIGURAR TIMESTAMPS POR BASE DE DATOS"
    echo "───────────────────────────────────────────────────────────"
    echo "Puedes usar diferentes timestamps para cada tipo de base de datos."
    echo "Deja en blanco para omitir la restauración de ese tipo."
    echo ""
    
    read -p "Timestamp para Estructura (docker-compose, .env): " STRUCTURE_TS
    read -p "Timestamp para MongoDB (ej: 20260105_131322): " MONGO_TS
    read -p "Timestamp para Milvus (ej: 20260105_131500): " MILVUS_TS
    read -p "Timestamp para PostgreSQL (ej: 20251231_112400): " POSTGRES_TS
    
    echo ""
    log_header "📋 RESUMEN DE RESTAURACIÓN"
    echo "───────────────────────────────────────────────────────────"
    [ -n "$STRUCTURE_TS" ] && echo "   🏗️  Estructura: $STRUCTURE_TS"
    [ -n "$MONGO_TS" ] && echo "   🍃 MongoDB:    $MONGO_TS"
    [ -n "$MILVUS_TS" ] && echo "   🔷 Milvus:     $MILVUS_TS"
    [ -n "$POSTGRES_TS" ] && echo "   🐘 PostgreSQL: $POSTGRES_TS"
    
    if [ -z "$STRUCTURE_TS" ] && [ -z "$MONGO_TS" ] && [ -z "$MILVUS_TS" ] && [ -z "$POSTGRES_TS" ]; then
        log_error "No se seleccionó ningún backup"
        exit 1
    fi
    
    echo ""
    log_header "⚠️  ADVERTENCIA IMPORTANTE"
    echo "───────────────────────────────────────────────────────────"
    echo "   Esta operación:"
    echo "   • Detendrá TODOS los contenedores de bases de datos"
    echo "   • Sobrescribirá TODOS los datos actuales"
    echo ""
    
    read -p "   ¿Continuar? (escribe 'RESTAURAR' para confirmar): " confirm
    
    if [ "$confirm" != "RESTAURAR" ]; then
        log_warning "Operación cancelada"
        exit 0
    fi
    
    # Restaurar estructura primero (si se especificó)
    [ -n "$STRUCTURE_TS" ] && restore_structure "$STRUCTURE_TS"
    
    # Detener contenedores
    stop_containers
    
    # Restaurar cada base de datos
    [ -n "$MONGO_TS" ] && restore_mongodb "$MONGO_TS"
    [ -n "$MILVUS_TS" ] && restore_milvus "$MILVUS_TS"
    [ -n "$POSTGRES_TS" ] && restore_postgresql "$POSTGRES_TS"
    
    # Iniciar contenedores
    start_containers
    
    sleep 5
    
    # Verificar estado
    verify_status
    
    # Resumen final
    echo ""
    log_header "📊 RESUMEN DE RESTAURACIÓN"
    echo "═══════════════════════════════════════════════════════════"
    echo -e "   ${GREEN}✅ Restaurados: $RESTORED_COUNT volúmenes${NC}"
    echo -e "   ${YELLOW}⏭️  Saltados:    $SKIPPED_COUNT volúmenes${NC}"
    echo -e "   ${RED}❌ Fallidos:    $FAILED_COUNT volúmenes${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# Ayuda
show_help() {
    echo "Uso: $0 [comando|timestamp]"
    echo ""
    echo "Comandos:"
    echo "  list              - Listar backups disponibles"
    echo "  help              - Mostrar esta ayuda"
    echo "  interactive       - Modo interactivo (por defecto)"
    echo "  advanced          - Modo avanzado (timestamps diferentes por DB)"
    echo ""
    echo "Restaurar:"
    echo "  $0 <TIMESTAMP>    - Restaurar backup específico"
    echo ""
    echo "Ejemplos:"
    echo "  $0 list"
    echo "  $0 20260105_131322"
    echo "  $0 interactive"
    echo "  $0 advanced"
    echo ""
    echo "Opciones avanzadas:"
    echo "  --structure-only <TS>   Restaurar solo estructura (docker-compose)"
    echo "  --mongodb-only <TS>     Restaurar solo MongoDB"
    echo "  --milvus-only <TS>      Restaurar solo Milvus"
    echo "  --postgres-only <TS>    Restaurar solo PostgreSQL"
}

# ============================================
# MAIN
# ============================================

print_banner
check_qnap

case "${1:-interactive}" in
    list|--list|-l)
        list_available_backups
        ;;
    help|--help|-h)
        show_help
        ;;
    interactive)
        TIMESTAMP=$(select_timestamp)
        restore_all "$TIMESTAMP"
        ;;
    advanced|--advanced|-a)
        restore_with_specific_timestamps
        ;;
    --structure-only)
        if [ -z "$2" ]; then
            log_error "Especifica el timestamp"
            exit 1
        fi
        restore_structure "$2"
        ;;
    --mongodb-only)
        if [ -z "$2" ]; then
            log_error "Especifica el timestamp"
            exit 1
        fi
        stop_containers
        restore_mongodb "$2"
        start_containers
        verify_status
        ;;
    --milvus-only)
        if [ -z "$2" ]; then
            log_error "Especifica el timestamp"
            exit 1
        fi
        stop_containers
        restore_milvus "$2"
        start_containers
        verify_status
        ;;
    --postgres-only)
        if [ -z "$2" ]; then
            log_error "Especifica el timestamp"
            exit 1
        fi
        stop_containers
        restore_postgresql "$2"
        start_containers
        verify_status
        ;;
    --full-restore)
        # Restauración completa desde cero (estructura + datos + iniciar contenedores)
        if [ -z "$2" ]; then
            log_error "Especifica el timestamp"
            exit 1
        fi
        log_header "🔄 RESTAURACIÓN COMPLETA DESDE CERO"
        echo "───────────────────────────────────────────────────────────"
        echo "   Esta opción restaurará:"
        echo "   • Estructura (docker-compose.yml, .env)"
        echo "   • Datos de MongoDB, Milvus y PostgreSQL"
        echo "   • Iniciará todos los contenedores"
        echo ""
        restore_structure "$2"
        stop_containers
        restore_mongodb "$2"
        restore_milvus "$2"
        restore_postgresql "$2"
        start_containers
        verify_status
        ;;
    *)
        # Asumir que es un timestamp
        if [ -n "$1" ]; then
            restore_all "$1"
        else
            show_help
        fi
        ;;
esac