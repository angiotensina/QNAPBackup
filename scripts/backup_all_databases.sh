#!/bin/bash
# ============================================
# Backup Completo: MongoDB + Milvus + PostgreSQL
# Mantiene integridad referencial entre todas las DBs
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "=================================================="
echo "   BACKUP COMPLETO: TODAS LAS BASES DE DATOS"
echo "   MongoDB + Milvus + PostgreSQL"
echo "   Fecha: $(date)"
echo "=================================================="
echo ""
echo "📊 Arquitectura de Bases de Datos:"
echo "   🍃 MongoDB (Parent)   -> Documentos y metadatos"
echo "   🔷 Milvus (Child)     -> Vectores embeddings"
echo "   🐘 PostgreSQL         -> Datos relacionales, pgvector"
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
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/postgres"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/logs"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/structure"

# Ruta a la estructura de las bases de datos
DBMAKER_PATH="${DBMAKER_PATH:-/Users/joaquinchamorromohedas/Desktop/QNAPBackup/CONSTRUCCION BDS/DBMakerOK}"

# Variables para tracking de éxito
MONGO_SUCCESS=false
MILVUS_SUCCESS=false
POSTGRES_SUCCESS=false
STRUCTURE_SUCCESS=false

# 2. Backup de la estructura de bases de datos (docker-compose, .env)
echo "📌 Paso 2: Backup de estructura de bases de datos..."
STRUCTURE_BACKUP_PATH="$QNAP_MOUNT_POINT/milvus-backups/structure/dbmaker_${TIMESTAMP}"
mkdir -p "$STRUCTURE_BACKUP_PATH"

if [ -d "$DBMAKER_PATH" ]; then
    # Copiar toda la carpeta DBMakerOK
    cp -R "$DBMAKER_PATH"/* "$STRUCTURE_BACKUP_PATH/" 2>/dev/null && {
        STRUCTURE_SUCCESS=true
        echo "✅ Estructura de BDs guardada en: $STRUCTURE_BACKUP_PATH"
        echo "   📁 Incluye: mongo/, postgres/, milvus/, redis/, neo4j/"
    } || {
        echo "⚠️  Error copiando estructura de BDs"
    }
else
    echo "⚠️  No se encontró la estructura en: $DBMAKER_PATH"
fi
echo ""

# 3. Backup de MongoDB (Parent)
echo "📌 Paso 3: Backup de MongoDB (Parent - Documentos)..."
if "$SCRIPT_DIR/backup_mongodb_docker.sh"; then
    MONGO_SUCCESS=true
    echo "✅ Backup de MongoDB completado"
else
    echo "⚠️  Backup de MongoDB falló, continuando..."
fi
echo ""

# 4. Backup de Milvus (Child)
echo "📌 Paso 4: Backup de Milvus (Child - Vectores)..."
if "$SCRIPT_DIR/backup_volumes_docker.sh"; then
    MILVUS_SUCCESS=true
    echo "✅ Backup de Milvus completado"
else
    echo "⚠️  Backup de Milvus falló, continuando..."
fi
echo ""

# 5. Backup de PostgreSQL
echo "📌 Paso 5: Backup de PostgreSQL (Datos relacionales)..."
if "$SCRIPT_DIR/backup_postgres_docker.sh"; then
    POSTGRES_SUCCESS=true
    echo "✅ Backup de PostgreSQL completado"
else
    echo "⚠️  Backup de PostgreSQL falló, continuando..."
fi
echo ""

# 6. Generar metadatos de consistencia
echo "📌 Paso 6: Generando metadatos de consistencia..."
CONSISTENCY_FILE="$QNAP_MOUNT_POINT/milvus-backups/backup_full_${TIMESTAMP}.json"

cat > "$CONSISTENCY_FILE" << EOF
{
    "backup_session": "$TIMESTAMP",
    "backup_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "backup_type": "full_database_backup",
    "databases_included": {
        "structure": {
            "success": $STRUCTURE_SUCCESS,
            "path": "structure/dbmaker_${TIMESTAMP}",
            "description": "Docker-compose y archivos .env para recrear contenedores"
        },
        "mongodb": {
            "success": $MONGO_SUCCESS,
            "path": "mongodb/mongodb_backup_${TIMESTAMP}",
            "role": "Parent - Documentos y metadatos"
        },
        "milvus": {
            "success": $MILVUS_SUCCESS,
            "path": "volumes/milvus_backup_${TIMESTAMP}",
            "role": "Child - Vectores/embeddings"
        },
        "postgresql": {
            "success": $POSTGRES_SUCCESS,
            "path": "postgres/postgres_backup_${TIMESTAMP}",
            "role": "Datos relacionales y pgvector"
        }
    },
    "consistency_info": {
        "description": "Backup completo de todas las bases de datos Docker",
        "must_restore_together": true,
        "restore_order": ["mongodb", "milvus", "postgresql"]
    },
    "parent_child_architecture": {
        "pairs": [
            {"mongodb": "mongo1:27020", "milvus": "milvus-standalone-1:19530"},
            {"mongodb": "mongo2:27021", "milvus": "milvus-standalone-2:19531"},
            {"mongodb": "mongo3:27022", "milvus": "milvus-standalone-3:19532"},
            {"mongodb": "mongo4:27023", "milvus": "milvus-standalone-4:19533"},
            {"mongodb": "mongo5:27024", "milvus": "milvus-standalone-5:19534"},
            {"mongodb": "mongo6:27017", "milvus": "macrochat-milvus:19540"}
        ]
    },
    "postgresql_instances": [
        "postgres-gdash (postgres:17)",
        "medimecum-postgres (postgres:16-alpine)",
        "usreaderplus-db (postgres:16-alpine)",
        "macrochat-postgres (pgvector/pgvector:pg16)",
        "postgres_graph_clinical (postgres:16-alpine)",
        "agents-postgres (postgres:16-alpine)",
        "pgvector-container (pgvector/pgvector:pg16)",
        "postgres_db1-5 (postgres:latest)"
    ],
    "restore_instructions": {
        "warning": "IMPORTANTE: Para mantener consistencia, restaurar todos los backups del MISMO timestamp",
        "steps": [
            "1. Copiar estructura desde structure/dbmaker_TIMESTAMP a ubicación deseada",
            "2. Restaurar volúmenes de MongoDB",
            "3. Restaurar volúmenes de Milvus",
            "4. Restaurar volúmenes de PostgreSQL",
            "5. Ejecutar docker compose up -d en cada carpeta (mongo, postgres, milvus)",
            "6. Verificar integridad de todas las bases de datos"
        ],
        "structure_restore": "cp -R structure/dbmaker_TIMESTAMP/* /ruta/destino/"
    }
}
EOF

echo "✅ Metadatos guardados en: $CONSISTENCY_FILE"
echo ""

# Resumen final
STRUCTURE_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/structure" 2>/dev/null | cut -f1 || echo "N/A")
MONGO_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/mongodb" 2>/dev/null | cut -f1 || echo "N/A")
MILVUS_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/volumes" 2>/dev/null | cut -f1 || echo "N/A")
POSTGRES_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups/postgres" 2>/dev/null | cut -f1 || echo "N/A")
TOTAL_SIZE=$(du -sh "$QNAP_MOUNT_POINT/milvus-backups" 2>/dev/null | cut -f1 || echo "N/A")

echo "=================================================="
echo "   ✅ BACKUP COMPLETO FINALIZADO"
echo "=================================================="
echo ""
echo "📊 Resumen de Backups:"
echo "   🏗️  Estructura:  $STRUCTURE_SIZE $([ "$STRUCTURE_SUCCESS" = true ] && echo "✅" || echo "❌")"
echo "   🍃 MongoDB:     $MONGO_SIZE $([ "$MONGO_SUCCESS" = true ] && echo "✅" || echo "❌")"
echo "   🔷 Milvus:      $MILVUS_SIZE $([ "$MILVUS_SUCCESS" = true ] && echo "✅" || echo "❌")"
echo "   🐘 PostgreSQL:  $POSTGRES_SIZE $([ "$POSTGRES_SUCCESS" = true ] && echo "✅" || echo "❌")"
echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   📦 Total:       $TOTAL_SIZE"
echo ""
echo "📁 Ubicación: $QNAP_MOUNT_POINT/milvus-backups/"
echo "🏗️  Estructura: $QNAP_MOUNT_POINT/milvus-backups/structure/dbmaker_${TIMESTAMP}/"
echo ""
echo "💡 La estructura incluye docker-compose.yml y .env para recrear"
echo "   los contenedores desde cero si es necesario."
echo ""

# Estado de salida
if [ "$MONGO_SUCCESS" = true ] && [ "$MILVUS_SUCCESS" = true ] && [ "$POSTGRES_SUCCESS" = true ]; then
    echo "🎉 Todos los backups completados exitosamente!"
    exit 0
else
    echo "⚠️  Algunos backups fallaron. Revisa los logs para más detalles."
    exit 1
fi
