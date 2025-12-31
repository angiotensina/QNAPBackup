#!/bin/bash
# ============================================
# Restaurar Volúmenes Docker de Milvus desde QNAP
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

echo "=================================================="
echo "   RESTAURAR VOLÚMENES MILVUS DESDE QNAP"
echo "=================================================="

# Verificar que QNAP está montado
if ! mount | grep -q "$QNAP_MOUNT_POINT"; then
    echo "❌ QNAP no está montado. Ejecuta primero: ./mount_qnap.sh"
    exit 1
fi

# Listar backups disponibles
BACKUP_DIR="$QNAP_MOUNT_POINT/milvus-backups/volumes"
echo ""
echo "📁 Backups disponibles:"
echo "------------------------"

backups=($(ls -1d "$BACKUP_DIR"/milvus_backup_* 2>/dev/null | sort -r))

if [ ${#backups[@]} -eq 0 ]; then
    echo "❌ No se encontraron backups en $BACKUP_DIR"
    exit 1
fi

for i in "${!backups[@]}"; do
    backup_name=$(basename "${backups[$i]}")
    backup_size=$(du -sh "${backups[$i]}" | cut -f1)
    echo "  [$i] $backup_name ($backup_size)"
done

echo ""
read -p "🔢 Selecciona el número del backup a restaurar: " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#backups[@]}" ]; then
    echo "❌ Selección inválida"
    exit 1
fi

SELECTED_BACKUP="${backups[$selection]}"
echo ""
echo "📦 Backup seleccionado: $(basename $SELECTED_BACKUP)"

# Confirmar
echo ""
echo "⚠️  ADVERTENCIA: Esta acción sobrescribirá los volúmenes actuales!"
read -p "¿Estás seguro? (escribe 'SI' para confirmar): " confirm

if [ "$confirm" != "SI" ]; then
    echo "❌ Operación cancelada"
    exit 1
fi

# Función para restaurar un volumen
restore_volume() {
    local volume_name=$1
    local backup_file="$SELECTED_BACKUP/${volume_name}.tar.gz"
    
    if [ ! -f "$backup_file" ]; then
        echo "⚠️  No existe backup para $volume_name, saltando..."
        return 0
    fi
    
    echo "🔄 Restaurando volumen: $volume_name"
    
    # Crear volumen si no existe
    docker volume create "$volume_name" > /dev/null 2>&1 || true
    
    # Restaurar datos
    docker run --rm \
        -v "$volume_name":/target \
        -v "$SELECTED_BACKUP":/backup:ro \
        alpine:latest \
        sh -c "rm -rf /target/* && tar -xzf /backup/${volume_name}.tar.gz -C /target"
    
    if [ $? -eq 0 ]; then
        echo "✅ $volume_name restaurado"
    else
        echo "❌ Error restaurando $volume_name"
        return 1
    fi
}

echo ""
echo "🚀 Iniciando restauración..."

# Detener contenedores Milvus
echo "⏸️  Deteniendo contenedores Milvus..."
for instance in $MILVUS_INSTANCES; do
    docker stop "$instance" 2>/dev/null || true
done

# Restaurar volúmenes
for volume in "${MILVUS_VOLUMES[@]}"; do
    restore_volume "$volume"
done

# Reiniciar contenedores
echo ""
echo "▶️  Reiniciando contenedores Milvus..."
for instance in $MILVUS_INSTANCES; do
    docker start "$instance" 2>/dev/null || true
done

echo ""
echo "=================================================="
echo "   ✅ RESTAURACIÓN COMPLETADA"
echo "=================================================="
echo ""
echo "💡 Espera unos minutos para que Milvus se inicialice completamente"
echo "   Puedes verificar el estado con: docker ps | grep milvus"
