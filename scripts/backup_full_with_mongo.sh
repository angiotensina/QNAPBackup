#!/bin/bash
# ============================================
# Backup Completo: MongoDB + Milvus (Parent-Child)
# Mantiene integridad referencial entre ambas DBs
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "=================================================="
echo "   BACKUP COMPLETO: MONGODB + MILVUS"
echo "   Mantiene integridad Parent-Child"
echo "   Fecha: $(date)"
echo "=================================================="
echo ""
echo "📊 Arquitectura:"
echo "   MongoDB (Parent) -> Documentos y metadatos"
echo "   Milvus (Child)   -> Vectores embeddings"
echo ""

# 1. Verificar/Montar QNAP
echo "📌 Paso 1: Verificando conexión QNAP..."
if ! mount | grep -q "$QNAP_MOUNT_POINT\|$QNAP_SHARE"; then
    echo "⚠️  QNAP no montado, intentando montar automáticamente..."
    "$SCRIPT_DIR/automount_qnap.sh" || {
        # Último intento: pedir montaje manual vía Finder
        echo "🔄 Intentando abrir conexión en Finder..."
        open "smb://${QNAP_HOST}/${QNAP_SHARE}" 2>/dev/null
        sleep 5
    }
    
    # Verificar de nuevo
    if ! mount | grep -q "$QNAP_MOUNT_POINT\|$QNAP_SHARE"; then
        echo "❌ No se pudo montar QNAP automáticamente"
        echo "💡 Monta manualmente: smb://${QNAP_HOST}/${QNAP_SHARE}"
        exit 1
    fi
fi
echo "✅ QNAP montado"
echo ""

# Crear estructura de carpetas
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/mongodb"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/volumes"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/logs"

# 2. Backup de MongoDB (Parent)
echo "📌 Paso 2: Backup de MongoDB (Parent - Documentos)..."
"$SCRIPT_DIR/backup_mongodb.sh"
echo ""

# 3. Backup de Milvus (Child)
echo "📌 Paso 3: Backup de Milvus (Child - Vectores)..."
"$SCRIPT_DIR/backup_volumes.sh"
echo ""

# 4. Generar metadatos de consistencia
echo "📌 Paso 4: Generando metadatos de consistencia..."
CONSISTENCY_FILE="$QNAP_MOUNT_POINT/milvus-backups/backup_consistency_${TIMESTAMP}.json"

cat > "$CONSISTENCY_FILE" << EOF
{
    "backup_session": "$TIMESTAMP",
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "consistency_info": {
        "description": "Este backup mantiene la consistencia entre MongoDB y Milvus",
        "mongodb_backup": "mongodb/mongodb_backup_${TIMESTAMP}",
        "milvus_backup": "volumes/milvus_backup_${TIMESTAMP}",
        "must_restore_together": true
    },
    "parent_child_architecture": {
        "parent": {
            "database": "MongoDB",
            "role": "Almacena documentos originales y metadatos",
            "reference_field": "_id o document_id"
        },
        "child": {
            "database": "Milvus",
            "role": "Almacena vectores/embeddings de los documentos",
            "reference_field": "document_id (referencia a MongoDB)"
        }
    },
    "instance_pairs": [
        {"mongo": "mongo1:27020", "milvus": "milvus-standalone-1:19530"},
        {"mongo": "mongo2:27021", "milvus": "milvus-standalone-2:19531"},
        {"mongo": "mongo3:27022", "milvus": "milvus-standalone-3:19532"},
        {"mongo": "mongo4:27023", "milvus": "milvus-standalone-4:19533"},
        {"mongo": "mongo5:27024", "milvus": "milvus-standalone-5:19534"},
        {"mongo": "mongo6:27017", "milvus": "macrochat-milvus:19540"}
    ],
    "restore_instructions": {
        "warning": "IMPORTANTE: Restaurar MongoDB y Milvus del MISMO backup para mantener consistencia",
        "steps": [
            "1. Detener TODOS los contenedores (MongoDB y Milvus)",
            "2. Restaurar volúmenes de MongoDB",
            "3. Restaurar volúmenes de Milvus", 
            "4. Iniciar contenedores MongoDB",
            "5. Esperar que MongoDB esté healthy",
            "6. Iniciar contenedores Milvus",
            "7. Verificar integridad con script de verificación"
        ]
    }
}
EOF

echo "✅ Metadatos guardados en: $CONSISTENCY_FILE"
echo ""

# Resumen final
MONGO_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/mongodb" 2>/dev/null | cut -f1 || echo "N/A")
MILVUS_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/volumes" 2>/dev/null | cut -f1 || echo "N/A")

echo "=================================================="
echo "   ✅ BACKUP COMPLETO FINALIZADO"
echo "=================================================="
echo ""
echo "📊 Resumen:"
echo "   📁 MongoDB (Parent):  $MONGO_SIZE"
echo "   📁 Milvus (Child):    $MILVUS_SIZE"
echo "   📁 Ubicación: $QNAP_MOUNT_POINT/milvus-backups/"
echo ""
echo "💡 Recuerda: Al restaurar, hazlo de ambas bases de datos"
echo "   del MISMO backup para mantener la integridad referencial."
echo ""
