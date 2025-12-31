#!/bin/bash
# ============================================
# Configurar Backup Automático con Cron
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_full_with_mongo.sh"
LOG_FILE="$SCRIPT_DIR/../logs/cron_backup.log"

echo "=================================================="
echo "   CONFIGURACIÓN DE BACKUP AUTOMÁTICO"
echo "=================================================="
echo ""

# Crear directorio de logs
mkdir -p "$SCRIPT_DIR/../logs"

# Mostrar opciones
echo "Opciones de frecuencia:"
echo "  [1] Diario a las 2:00 AM"
echo "  [2] Cada 6 horas"
echo "  [3] Semanal (Domingos a las 3:00 AM)"
echo "  [4] Personalizado"
echo "  [5] Ver cron actual"
echo "  [6] Eliminar backup automático"
echo ""

read -p "Selecciona una opción: " option

case $option in
    1)
        CRON_SCHEDULE="0 2 * * *"
        DESCRIPTION="Diario a las 2:00 AM"
        ;;
    2)
        CRON_SCHEDULE="0 */6 * * *"
        DESCRIPTION="Cada 6 horas"
        ;;
    3)
        CRON_SCHEDULE="0 3 * * 0"
        DESCRIPTION="Semanal - Domingos a las 3:00 AM"
        ;;
    4)
        echo ""
        echo "Formato cron: minuto hora día-mes mes día-semana"
        echo "Ejemplo: '0 3 * * *' = Diario a las 3:00 AM"
        read -p "Introduce el schedule cron: " CRON_SCHEDULE
        DESCRIPTION="Personalizado: $CRON_SCHEDULE"
        ;;
    5)
        echo ""
        echo "📋 Tareas cron actuales relacionadas con Milvus backup:"
        crontab -l 2>/dev/null | grep -i "milvus\|QNAPBackup" || echo "No hay tareas configuradas"
        exit 0
        ;;
    6)
        echo "🗑️  Eliminando backup automático..."
        crontab -l 2>/dev/null | grep -v "QNAPBackup" | crontab -
        echo "✅ Backup automático eliminado"
        exit 0
        ;;
    *)
        echo "❌ Opción inválida"
        exit 1
        ;;
esac

# Crear entrada cron
CRON_ENTRY="$CRON_SCHEDULE $BACKUP_SCRIPT >> $LOG_FILE 2>&1"

# Añadir a crontab (evitando duplicados)
(crontab -l 2>/dev/null | grep -v "QNAPBackup"; echo "$CRON_ENTRY") | crontab -

echo ""
echo "✅ Backup automático configurado:"
echo "   📅 Frecuencia: $DESCRIPTION"
echo "   📜 Script: $BACKUP_SCRIPT"
echo "   📝 Log: $LOG_FILE"
echo ""
echo "💡 Usa 'crontab -l' para verificar la configuración"
