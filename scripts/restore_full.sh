#!/bin/bash
# ============================================
# Restaurar MongoDB + Milvus (Parent-Child)
# Mantiene integridad referencial
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

echo "=================================================="
echo "   RESTAURAR MONGODB + MILVUS"
echo "   (Mantiene integridad Parent-Child)"
echo "=================================================="
echo ""

# Verificar QNAP
if ! mount | grep -q "$QNAP_MOUNT_POINT"; then
    echo "❌ QNAP no está montado. Ejecuta primero: ./mount_qnap.sh"
    exit 1
fi

# Listar backups disponibles
echo "📁 Buscando backups de consistencia..."
BACKUP_DIR="$QNAP_MOUNT_POINT/milvus-backups"

# Buscar archivos de consistencia para encontrar backups completos
consistency_files=($(ls -1 "$BACKUP_DIR"/backup_consistency_*.json 2>/dev/null | sort -r))

if [ ${#consistency_files[@]} -eq 0 ]; then
    echo "⚠️  No se encontraron backups completos (MongoDB + Milvus)"
    echo "   Buscando backups individuales..."
    
    # Listar backups individuales
    echo ""
    echo "📦 Backups de Milvus:"
    ls -1d "$BACKUP_DIR/volumes"/milvus_backup_* 2>/dev/null | head -5 || echo "   Ninguno"
    
    echo ""
    echo "📦 Backups de MongoDB:"
    ls -1d "$BACKUP_DIR/mongodb"/mongodb_backup_* 2>/dev/null | head -5 || echo "   Ninguno"
    
    echo ""
    echo "❌ Para mantener integridad, ejecuta backup_full_with_mongo.sh primero"
    exit 1
fi

echo ""
echo "📋 Backups completos disponibles:"
echo "--------------------------------"
for i in "${!consistency_files[@]}"; do
    file="${consistency_files[$i]}"
    timestamp=$(basename "$file" | sed 's/backup_consistency_//' | sed 's/.json//')
    date_formatted=$(echo $timestamp | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
    echo "  [$i] $date_formatted"
done

echo ""
read -p "🔢 Selecciona el número del backup a restaurar: " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#consistency_files[@]}" ]; then
    echo "❌ Selección inválida"
    exit 1
fi

SELECTED_FILE="${consistency_files[$selection]}"
TIMESTAMP=$(basename "$SELECTED_FILE" | sed 's/backup_consistency_//' | sed 's/.json//')

MONGO_BACKUP="$BACKUP_DIR/mongodb/mongodb_backup_$TIMESTAMP"
MILVUS_BACKUP="$BACKUP_DIR/volumes/milvus_backup_$TIMESTAMP"

echo ""
echo "📦 Backup seleccionado: $TIMESTAMP"
echo "   MongoDB: $MONGO_BACKUP"
echo "   Milvus:  $MILVUS_BACKUP"

# Verificar que ambos existen
if [ ! -d "$MONGO_BACKUP" ]; then
    echo "⚠️  Backup de MongoDB no encontrado en: $MONGO_BACKUP"
fi
if [ ! -d "$MILVUS_BACKUP" ]; then
    echo "⚠️  Backup de Milvus no encontrado en: $MILVUS_BACKUP"
fi

# Confirmar
echo ""
echo "⚠️  ADVERTENCIA IMPORTANTE:"
echo "   - Se detendrán TODOS los contenedores MongoDB y Milvus"
echo "   - Se sobrescribirán TODOS los datos actuales"
echo "   - Este proceso puede tardar varios minutos"
echo ""
read -p "¿Estás seguro? (escribe 'RESTAURAR' para confirmar): " confirm

if [ "$confirm" != "RESTAURAR" ]; then
    echo "❌ Operación cancelada"
    exit 1
fi

echo ""
echo "🚀 Iniciando restauración..."

# Función para restaurar volumen
restore_volume() {
    local volume_name=$1
    local backup_path=$2
    local backup_file="$backup_path/${volume_name}.tar.gz"
    
    if [ ! -f "$backup_file" ]; then
        echo "⚠️  No existe backup para $volume_name"
        return 0
    fi
    
    echo "🔄 Restaurando: $volume_name"
    
    docker volume create "$volume_name" > /dev/null 2>&1 || true
    
    docker run --rm \
        -v "$volume_name":/target \
        -v "$backup_path":/backup:ro \
        alpine:latest \
        sh -c "rm -rf /target/* && tar -xzf /backup/${volume_name}.tar.gz -C /target"
    
    echo "✅ $volume_name restaurado"
}

# 1. Detener todos los contenedores
echo ""
echo "📌 Paso 1: Deteniendo contenedores..."
for instance in $MONGO_INSTANCES; do
    docker stop "$instance" 2>/dev/null && echo "   ⏸️  $instance detenido" || true
done
for instance in $MILVUS_INSTANCES; do
    docker stop "$instance" 2>/dev/null && echo "   ⏸️  $instance detenido" || true
done

# 2. Restaurar MongoDB
echo ""
echo "📌 Paso 2: Restaurando volúmenes MongoDB..."
if [ -d "$MONGO_BACKUP" ]; then
    for volume in "${MONGO_VOLUMES[@]}"; do
        restore_volume "$volume" "$MONGO_BACKUP"
    done
fi

# 3. Restaurar Milvus
echo ""
echo "📌 Paso 3: Restaurando volúmenes Milvus..."
if [ -d "$MILVUS_BACKUP" ]; then
    for volume in "${MILVUS_VOLUMES[@]}"; do
        restore_volume "$volume" "$MILVUS_BACKUP"
    done
fi

# 4. Iniciar MongoDB primero (Parent)
echo ""
echo "📌 Paso 4: Iniciando MongoDB (Parent)..."
for instance in $MONGO_INSTANCES; do
    docker start "$instance" 2>/dev/null && echo "   ▶️  $instance iniciado" || true
done

echo "⏳ Esperando que MongoDB esté listo..."
sleep 10

# 5. Iniciar Milvus (Child)
echo ""
echo "📌 Paso 5: Iniciando Milvus (Child)..."
for instance in $MILVUS_INSTANCES; do
    docker start "$instance" 2>/dev/null && echo "   ▶️  $instance iniciado" || true
done

echo ""
echo "⏳ Esperando que los servicios estén listos..."
sleep 15

# 6. Verificar estado
echo ""
echo "📌 Paso 6: Verificando estado..."
echo ""
echo "MongoDB:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -i mongo || echo "   ❌ No hay contenedores MongoDB corriendo"

echo ""
echo "Milvus:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -i milvus || echo "   ❌ No hay contenedores Milvus corriendo"

echo ""
echo "=================================================="
echo "   ✅ RESTAURACIÓN COMPLETADA"
echo "=================================================="
echo ""
echo "💡 Recomendaciones post-restauración:"
echo "   1. Verifica que todas las instancias estén 'healthy'"
echo "   2. Prueba la conexión a MongoDB y Milvus"
echo "   3. Verifica la integridad de los datos"
echo ""
