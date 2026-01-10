#!/bin/bash

################################################################################
# Script: update_containers.sh
# Descripción: Actualiza todos los contenedores excepto clinica-app
# Autor: Sistema de Backup QNAP
# Fecha: $(date +%Y-%m-%d)
################################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Función principal
main() {
    log_info "🚀 Iniciando actualización de contenedores..."
    
    # Verificar que estamos en el directorio correcto
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.manager.yml" ]; then
        log_error "No se encontraron archivos docker-compose en el directorio actual"
        exit 1
    fi
    
    # Pull de cambios de git (si estamos en un repo)
    if [ -d ".git" ]; then
        log_info "📦 Actualizando código desde Git..."
        git pull origin main || log_warning "No se pudo hacer git pull"
    fi
    
    # Obtener lista de todos los contenedores en ejecución
    log_info "🔍 Detectando contenedores en ejecución..."
    ALL_CONTAINERS=$(docker ps --format "{{.Names}}")
    
    # Filtrar contenedores que NO contengan "clinica-app"
    CONTAINERS_TO_UPDATE=""
    CLINICA_CONTAINERS=""
    
    for container in $ALL_CONTAINERS; do
        if [[ "$container" =~ clinica-app ]]; then
            CLINICA_CONTAINERS="$CLINICA_CONTAINERS $container"
            log_warning "⏭️  Omitiendo: $container (clinica-app)"
        else
            CONTAINERS_TO_UPDATE="$CONTAINERS_TO_UPDATE $container"
        fi
    done
    
    log_info "Contenedores a actualizar: $CONTAINERS_TO_UPDATE"
    log_warning "Contenedores EXCLUIDOS: $CLINICA_CONTAINERS"
    
    # Actualizar QNAP Backup Manager si existe
    if docker ps -q -f name=qnap-backup-manager > /dev/null 2>&1; then
        log_info "🔄 Actualizando QNAP Backup Manager..."
        docker-compose -f docker-compose.manager.yml pull
        docker-compose -f docker-compose.manager.yml up -d --build --force-recreate
        log_success "✅ QNAP Backup Manager actualizado"
    else
        log_info "⏭️  QNAP Backup Manager no está corriendo, omitiendo..."
    fi
    
    # Actualizar Milvus MongoDB Backup si existe
    if docker ps -q -f name=milvus-mongodb-backup > /dev/null 2>&1; then
        log_info "🔄 Actualizando Milvus MongoDB Backup..."
        docker-compose -f docker-compose.yml pull
        docker-compose -f docker-compose.yml up -d --build --force-recreate
        log_success "✅ Milvus MongoDB Backup actualizado"
    else
        log_info "⏭️  Milvus MongoDB Backup no está corriendo, omitiendo..."
    fi
    
    # Limpiar imágenes y recursos no utilizados
    log_info "🧹 Limpiando recursos Docker no utilizados..."
    docker image prune -f
    docker volume prune -f || true
    
    log_success "✅ Actualización completada exitosamente!"
    log_info "📊 Estado actual de contenedores:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Verificar que clinica-app sigue corriendo sin cambios
    log_info "🔍 Verificando integridad de clinica-app..."
    if docker ps -q -f name=clinica-app > /dev/null 2>&1; then
        CLINICA_UPTIME=$(docker inspect --format='{{.State.StartedAt}}' $(docker ps -q -f name=clinica-app) | head -n 1)
        log_success "✅ clinica-app intacto - Running since $CLINICA_UPTIME"
    else
        log_warning "⚠️  No se encontró ningún contenedor clinica-app corriendo"
    fi
    
    log_success "🎉 Proceso completado con éxito!"
}

# Ejecutar función principal
main "$@"
