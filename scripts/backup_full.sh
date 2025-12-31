#!/bin/bash
# ============================================
# Backup Completo: Volúmenes + Colecciones
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "   BACKUP COMPLETO DE MILVUS"
echo "   Fecha: $(date)"
echo "=================================================="
echo ""

# 1. Montar QNAP
echo "📌 Paso 1: Verificando conexión QNAP..."
"$SCRIPT_DIR/mount_qnap.sh"
echo ""

# 2. Backup de Volúmenes Docker
echo "📌 Paso 2: Backup de volúmenes Docker..."
"$SCRIPT_DIR/backup_volumes.sh"
echo ""

# 3. Backup de Colecciones (schemas y metadata)
echo "📌 Paso 3: Backup de colecciones Milvus..."
python3 "$SCRIPT_DIR/backup_collections.py"
echo ""

echo "=================================================="
echo "   ✅ BACKUP COMPLETO FINALIZADO"
echo "   Fecha: $(date)"
echo "=================================================="
