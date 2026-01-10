# 🚀 Configuración de GitHub Actions para Deploy Automático

Este documento explica cómo configurar los secretos de GitHub para que el workflow de deploy funcione correctamente.

## 📋 Secretos Requeridos

El workflow [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) requiere los siguientes secretos configurados en tu repositorio de GitHub:

### 1. `SSH_PRIVATE_KEY`
**Descripción:** Clave privada SSH para conectarse al servidor remoto

**Cómo obtenerla:**
```bash
# En tu máquina local, genera un par de claves SSH (si no las tienes)
ssh-keygen -t rsa -b 4096 -C "github-actions@qnapbackup" -f ~/.ssh/github_actions_qnap

# Copiar la clave PÚBLICA al servidor remoto
ssh-copy-id -i ~/.ssh/github_actions_qnap.pub usuario@servidor-remoto

# Copiar el contenido de la clave PRIVADA para GitHub Secrets
cat ~/.ssh/github_actions_qnap
```

**Valor:** Contenido completo de la clave privada SSH (incluye `-----BEGIN OPENSSH PRIVATE KEY-----` y `-----END OPENSSH PRIVATE KEY-----`)

---

### 2. `REMOTE_HOST`
**Descripción:** Dirección IP o hostname del servidor remoto

**Ejemplo:**
```
192.168.1.100
```
o
```
mi-servidor.ejemplo.com
```

**Valor:** IP o hostname de tu servidor remoto donde están los contenedores

---

### 3. `REMOTE_USER`
**Descripción:** Usuario SSH para conectarse al servidor remoto

**Ejemplo:**
```
joaquin
```

**Valor:** Nombre de usuario SSH con permisos para ejecutar Docker

---

### 4. `REMOTE_PATH`
**Descripción:** Ruta absoluta en el servidor remoto donde está el repositorio

**Ejemplo:**
```
/home/joaquin/QNAPBackup
```

**Valor:** Ruta completa al directorio del proyecto en el servidor remoto

---

## 🔐 Cómo Configurar los Secretos en GitHub

1. Ve a tu repositorio en GitHub
2. Navega a **Settings** → **Secrets and variables** → **Actions**
3. Haz clic en **New repository secret**
4. Para cada secreto:
   - Ingresa el **Name** (nombre exacto como aparece arriba)
   - Ingresa el **Value** (valor correspondiente)
   - Haz clic en **Add secret**

## ✅ Verificación de Configuración

### Checklist antes del primer deploy:

- [ ] Clave SSH pública agregada al servidor remoto (~/.ssh/authorized_keys)
- [ ] Usuario remoto tiene permisos para ejecutar Docker sin sudo
- [ ] Repositorio clonado en el servidor remoto en la ruta especificada
- [ ] Git configurado en el servidor remoto para hacer pull
- [ ] Docker y Docker Compose instalados en el servidor remoto
- [ ] Todos los 4 secretos configurados en GitHub

### Probar conexión SSH:

```bash
# Desde tu máquina local
ssh -i ~/.ssh/github_actions_qnap usuario@servidor-remoto "docker ps"
```

Si esto funciona, el workflow debería funcionar también.

## 🎯 Cómo Funciona el Workflow

### Triggers (Disparadores):

1. **Push a main:** Se dispara automáticamente al hacer push directo a la rama main
2. **Pull Request merged:** Se dispara cuando se hace merge de un PR a main
3. **Manual (workflow_dispatch):** Puedes ejecutarlo manualmente desde la pestaña "Actions" en GitHub

### Exclusiones:

El workflow **NO actualizará** ningún contenedor que contenga `clinica-app` en su nombre. Esto protege la base de datos clínica de actualizaciones accidentales.

### Contenedores que SÍ se actualizan:

- `qnap-backup-manager`
- `milvus-mongodb-backup`
- Cualquier otro contenedor que NO sea `clinica-app`

## 🚀 Ejecución Manual del Workflow

Si quieres ejecutar el workflow manualmente (sin hacer push):

1. Ve a tu repositorio en GitHub
2. Navega a la pestaña **Actions**
3. Selecciona **Deploy to Remote Server**
4. Haz clic en **Run workflow**
5. Selecciona la rama `main`
6. Haz clic en **Run workflow** (verde)

## 📊 Monitoreo del Deploy

Durante la ejecución, el workflow:

1. ✅ Hace checkout del código
2. ✅ Configura la clave SSH
3. ✅ Se conecta al servidor remoto
4. ✅ Pull de cambios desde GitHub
5. ✅ Actualiza contenedores (excepto clinica-app)
6. ✅ Verifica el estado de los contenedores
7. ✅ Confirma que clinica-app no fue modificado

Puedes ver los logs en tiempo real en la pestaña **Actions** de GitHub.

## 🐛 Troubleshooting

### Error: "Permission denied (publickey)"
- Verifica que `SSH_PRIVATE_KEY` esté configurado correctamente
- Verifica que la clave pública esté en el servidor remoto

### Error: "git pull failed"
- Verifica que el usuario tenga permisos para hacer git pull
- Puede que necesites configurar Git credentials en el servidor

### Error: "docker: command not found"
- Verifica que Docker esté instalado en el servidor remoto
- Verifica que el usuario tenga permisos para ejecutar Docker

### Los contenedores no se actualizan
- Verifica que `REMOTE_PATH` apunte al directorio correcto
- Verifica que existan los archivos docker-compose.yml en esa ruta

## 📝 Script Local para Testing

También puedes usar el script local para probar la actualización:

```bash
# En el servidor remoto
cd /ruta/al/proyecto/QNAPBackup
./scripts/update_containers.sh
```

Este script hace lo mismo que el workflow, pero localmente.

## 🔄 Frecuencia de Actualizaciones

El workflow se ejecuta:
- Cada vez que haces **push** a `main`
- Cada vez que se **mergea un PR** a `main`
- **Manualmente** cuando tú lo ejecutes desde GitHub Actions

## 🛡️ Protección de clinica-app

El workflow está diseñado para **NUNCA** actualizar contenedores que incluyan `clinica-app` en su nombre. Esto incluye:
- `clinica-app_postgres`
- `clinica-app_milvus`
- `clinica-app_*` (cualquier variante)

Si necesitas actualizar estos contenedores, debes hacerlo manualmente en el servidor.

## 📞 Soporte

Si tienes problemas con el deploy:
1. Revisa los logs en la pestaña Actions de GitHub
2. Verifica la configuración de los secretos
3. Prueba la conexión SSH manualmente
4. Ejecuta el script `update_containers.sh` directamente en el servidor para debug
