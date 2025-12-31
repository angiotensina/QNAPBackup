#!/bin/bash
# ============================================
# Auto-montar QNAP share usando Keychain
# Se ejecuta automáticamente al iniciar sesión
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

LOG_FILE="$SCRIPT_DIR/../logs/automount.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "🔌 Intentando montar QNAP automáticamente..."

# Verificar si ya está montado
if mount | grep -q "$QNAP_MOUNT_POINT\|$QNAP_SHARE"; then
    log "✅ QNAP ya está montado"
    exit 0
fi

# Verificar conectividad
if ! ping -c 1 -W 2 "$QNAP_HOST" > /dev/null 2>&1; then
    log "❌ QNAP no accesible en $QNAP_HOST"
    exit 1
fi

# Intentar obtener contraseña del Keychain
QNAP_PASSWORD=$(security find-internet-password -a "$QNAP_USER" -s "$QNAP_HOST" -w 2>/dev/null)

if [ -z "$QNAP_PASSWORD" ]; then
    log "⚠️ Contraseña no encontrada en Keychain"
    # Intentar montar con credenciales guardadas en Finder
    osascript -e "try" \
        -e "mount volume \"smb://${QNAP_HOST}/${QNAP_SHARE}\"" \
        -e "end try" 2>/dev/null
else
    # Montar con credenciales del Keychain
    ENCODED_USER=$(echo "$QNAP_USER" | sed 's/\\/%5C/g' | sed 's/ /%20/g')
    
    osascript -e "try" \
        -e "mount volume \"smb://${QNAP_HOST}/${QNAP_SHARE}\" as user name \"${QNAP_USER}\" with password \"${QNAP_PASSWORD}\"" \
        -e "end try" 2>/dev/null
fi

# Verificar si se montó
sleep 2
if mount | grep -q "$QNAP_SHARE"; then
    log "✅ QNAP montado correctamente"
    exit 0
else
    log "❌ No se pudo montar QNAP automáticamente"
    exit 1
fi
