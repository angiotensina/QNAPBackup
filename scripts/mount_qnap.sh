#!/bin/bash
# ============================================
# Script para montar QNAP share
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.env"

echo "🔌 Montando QNAP share..."

# Crear punto de montaje si no existe
if [ ! -d "$QNAP_MOUNT_POINT" ]; then
    echo "📁 Creando directorio de montaje: $QNAP_MOUNT_POINT"
    sudo mkdir -p "$QNAP_MOUNT_POINT"
fi

# Verificar si ya está montado
if mount | grep -q "$QNAP_MOUNT_POINT"; then
    echo "✅ QNAP ya está montado en $QNAP_MOUNT_POINT"
else
    echo "🔗 Montando //192.168.1.140/$QNAP_SHARE en $QNAP_MOUNT_POINT"
    
    # Intentar obtener contraseña del Keychain de macOS
    QNAP_PASSWORD=$(security find-internet-password -a "$QNAP_USER" -s "$QNAP_HOST" -w 2>/dev/null) || {
        echo "🔐 Contraseña no encontrada en Keychain"
        echo -n "🔑 Introduce la contraseña para $QNAP_USER@$QNAP_HOST: "
        read -s QNAP_PASSWORD
        echo ""
        
        # Opción para guardar en Keychain
        echo -n "💾 ¿Guardar contraseña en Keychain? (s/n): "
        read save_pwd
        if [ "$save_pwd" = "s" ] || [ "$save_pwd" = "S" ]; then
            security add-internet-password -a "$QNAP_USER" -s "$QNAP_HOST" -w "$QNAP_PASSWORD" -U 2>/dev/null || true
            echo "✅ Contraseña guardada en Keychain"
        fi
    }
    
    # Codificar usuario para URL (reemplazar \ por ;)
    ENCODED_USER=$(echo "$QNAP_USER" | sed 's/\\/%5C/g')
    
    # Para macOS usando SMB con contraseña
    mount -t smbfs "//${ENCODED_USER}:${QNAP_PASSWORD}@${QNAP_HOST}/${QNAP_SHARE}" "$QNAP_MOUNT_POINT" 2>/dev/null || {
        echo "⚠️  Primer intento fallido, probando método alternativo..."
        
        # Método alternativo usando osascript para Finder
        osascript -e "try" \
            -e "mount volume \"smb://${QNAP_HOST}/${QNAP_SHARE}\" as user name \"${QNAP_USER}\" with password \"${QNAP_PASSWORD}\"" \
            -e "end try" 2>/dev/null || {
            echo "❌ Error montando QNAP automáticamente"
            echo "💡 Por favor, monta el share manualmente:"
            echo "   1. Finder -> Ir -> Conectar al servidor (⌘K)"
            echo "   2. Escribir: smb://${QNAP_HOST}/${QNAP_SHARE}"
            echo "   3. Usuario: ${QNAP_USER}"
            echo "   4. Introducir contraseña"
            open "smb://${QNAP_HOST}/${QNAP_SHARE}"
            
            echo ""
            echo -n "⏳ Presiona ENTER cuando hayas montado el share manualmente..."
            read
            
            # Verificar si se montó
            if ! mount | grep -q "$QNAP_SHARE"; then
                echo "❌ El share no se montó correctamente"
                exit 1
            fi
        }
    }
    
    echo "✅ QNAP montado correctamente"
fi

# Crear estructura de carpetas en QNAP
echo "📂 Creando estructura de carpetas en QNAP..."
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/volumes"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/collections"
mkdir -p "$QNAP_MOUNT_POINT/milvus-backups/logs"

echo "✅ Estructura de carpetas creada"
