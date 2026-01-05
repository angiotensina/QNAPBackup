# 🗄️ QNAP Backup Manager

Sistema completo de gestión de backups de volúmenes Docker hacia QNAP NAS, con interfaz web React, API FastAPI y **programación de backups automáticos**.

![Docker](https://img.shields.io/badge/Docker-Ready-blue)
![React](https://img.shields.io/badge/React-18-61dafb)
![FastAPI](https://img.shields.io/badge/FastAPI-0.109-009688)
![APScheduler](https://img.shields.io/badge/APScheduler-3.10-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## 📋 Características

- ✅ **Backup completo** de volúmenes Docker (MongoDB, Milvus, PostgreSQL, Redis)
- ✅ **Programación de backups** con scheduler profesional (diario, semanal, mensual, cron, intervalo)
- ✅ **Interfaz web** moderna con React + TailwindCSS
- ✅ **API REST** con FastAPI y documentación Swagger
- ✅ **Restauración** selectiva por componentes
- ✅ **Monitoreo** en tiempo real de tareas
- ✅ **Presets** de configuración para schedules comunes
- ✅ **Historial** de ejecuciones programadas
- ✅ **Dockerizado** - Listo para desplegar en puerto 6640
- ✅ **Logs** detallados de cada operación

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    QNAP Backup Manager                       │
│                       (Puerto 6640)                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   Frontend  │───▶│   Backend   │───▶│    Scripts      │  │
│  │   (React)   │    │  (FastAPI)  │    │    (Bash)       │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
│                            │                    │            │
│                            ▼                    ▼            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Docker Socket                         ││
│  └─────────────────────────────────────────────────────────┘│
│                            │                                 │
└────────────────────────────│─────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Docker Volumes                            │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   MongoDB    │    Milvus    │  PostgreSQL  │     Redis      │
│  (6 inst.)   │  (5 inst.)   │              │                │
└──────────────┴──────────────┴──────────────┴────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      QNAP NAS                                │
│               /Volumes/JOAQUIN/milvus-backups                │
├─────────────┬─────────────┬─────────────┬───────────────────┤
│   mongodb/  │   volumes/  │  postgres/  │      logs/        │
└─────────────┴─────────────┴─────────────┴───────────────────┘
```

## 🚀 Inicio Rápido

### Requisitos

- Docker Desktop
- QNAP NAS montado en `/Volumes/JOAQUIN` (macOS)
- Puerto 6640 disponible

### Despliegue

```bash
# 1. Clonar el repositorio
cd ~/Desktop/QNAPBackup

# 2. Verificar que QNAP está montado
ls /Volumes/JOAQUIN

# 3. Construir y ejecutar
docker-compose -f docker-compose.manager.yml up -d --build

# 4. Acceder a la interfaz
open http://localhost:6640
```

### Verificar funcionamiento

```bash
# Health check
curl http://localhost:6640/api/health

# Estado del sistema
curl http://localhost:6640/api/status

# Documentación API
open http://localhost:6640/api/docs
```

## 📖 Uso

### Interfaz Web

Accede a `http://localhost:6640` para usar la interfaz gráfica:

1. **Dashboard**: Vista general del sistema, estadísticas y acciones rápidas
2. **Backups**: Historial de backups y opciones de restauración
3. **Programación**: Configurar backups automáticos con presets o personalizados
4. **Volúmenes**: Lista de volúmenes Docker por categoría
5. **Tareas**: Monitoreo de tareas en ejecución

### API REST

```bash
# Iniciar backup global
curl -X POST http://localhost:6640/api/backup/global

# Iniciar backup de MongoDB
curl -X POST http://localhost:6640/api/backup/mongodb

# Iniciar backup de Milvus
curl -X POST http://localhost:6640/api/backup/milvus

# Listar backups disponibles
curl http://localhost:6640/api/backups

# Estado de una tarea
curl http://localhost:6640/api/tasks/{task_id}

# Restaurar backup
curl -X POST http://localhost:6640/api/restore \
  -H "Content-Type: application/json" \
  -d '{"timestamp": "20260105_131322", "components": ["mongodb", "milvus"]}'
```

### Programación de Backups

```bash
# Ver presets disponibles
curl http://localhost:6640/api/schedules/presets

# Crear schedule desde preset
curl -X POST http://localhost:6640/api/schedules/from-preset/daily_night

# Crear schedule personalizado
curl -X POST http://localhost:6640/api/schedules \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Backup MongoDB Nocturno",
    "description": "Backup de MongoDB a las 3:00 AM",
    "backup_types": ["mongodb"],
    "schedule_type": "daily",
    "time_of_day": "03:00"
  }'

# Crear schedule con cron expression
curl -X POST http://localhost:6640/api/schedules \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Backup cada hora laboral",
    "backup_types": ["mongodb"],
    "schedule_type": "cron",
    "cron_expression": "0 9-18 * * 1-5"
  }'

# Pausar schedule
curl -X POST http://localhost:6640/api/schedules/{schedule_id}/pause

# Reanudar schedule
curl -X POST http://localhost:6640/api/schedules/{schedule_id}/resume

# Ejecutar schedule ahora
curl -X POST http://localhost:6640/api/schedules/{schedule_id}/run-now

# Ver estadísticas del scheduler
curl http://localhost:6640/api/schedules/stats

# Ver historial de ejecuciones
curl http://localhost:6640/api/schedules/history
```

#### Presets Disponibles

| Preset ID | Nombre | Descripción |
|-----------|--------|-------------|
| `daily_night` | Backup Diario Nocturno | Backup global a las 2:00 AM |
| `weekdays_morning` | Backup Días Laborables | MongoDB+PostgreSQL L-V 6:00 AM |
| `weekly_full` | Backup Semanal | Backup global domingos 3:00 AM |
| `monthly_archive` | Backup Mensual | Backup global día 1 a las 4:00 AM |
| `every_6_hours` | Cada 6 horas | Backup MongoDB cada 6 horas |

#### Tipos de Schedule

| Tipo | Parámetros | Ejemplo |
|------|------------|---------|
| `cron` | `cron_expression` | `"0 2 * * *"` (2:00 AM diario) |
| `interval` | `interval_minutes` | `360` (cada 6 horas) |
| `daily` | `time_of_day` | `"02:00"` |
| `weekly` | `time_of_day`, `days_of_week` | `"03:00"`, `[0,1,2,3,4]` (L-V) |
| `monthly` | `time_of_day`, `days_of_month` | `"04:00"`, `[1,15]` (días 1 y 15) |
| `once` | `run_date` | `"2026-01-10 02:00:00"` |

### Scripts Directos

Los scripts también pueden ejecutarse directamente:

```bash
# Backup global completo
./scripts/backup_global.sh

# Backup solo MongoDB
./scripts/backup_mongodb_docker.sh

# Backup solo Milvus
./scripts/backup_volumes_docker.sh

# Restaurar
./scripts/restore_global.sh list
./scripts/restore_global.sh 20260105_131322
```

## 📁 Estructura del Proyecto

```
QNAPBackup/
├── backend/
│   ├── main.py              # API FastAPI
│   ├── scheduler.py         # Sistema de programación (APScheduler)
│   └── requirements.txt     # Dependencias Python
├── frontend/
│   ├── src/
│   │   ├── App.tsx          # Componente principal React
│   │   ├── api.ts           # Cliente API
│   │   ├── main.tsx         # Punto de entrada
│   │   └── index.css        # Estilos Tailwind
│   ├── package.json
│   ├── vite.config.ts
│   └── tailwind.config.js
├── scripts/
│   ├── backup_global.sh     # Backup completo
│   ├── backup_mongodb_docker.sh
│   ├── backup_volumes_docker.sh
│   ├── backup_postgres_docker.sh
│   ├── restore_global.sh    # Restauración
│   └── ...
├── data/                    # Datos persistentes (schedules)
├── logs/                    # Logs locales
├── config.env               # Configuración
├── Dockerfile.manager       # Dockerfile producción
├── docker-compose.manager.yml
└── README.md
```

## ⚙️ Configuración

### Variables de Entorno

| Variable | Descripción | Default |
|----------|-------------|---------|
| `QNAP_HOST` | IP del QNAP NAS | `192.168.1.140` |
| `QNAP_SHARE` | Nombre del share SMB | `JOAQUIN` |
| `QNAP_MOUNT_POINT` | Punto de montaje | `/Volumes/JOAQUIN` |
| `QNAP_USER` | Usuario QNAP | `CARMENVELASCO\joaquin` |
| `TZ` | Timezone | `Europe/Madrid` |

### config.env

```bash
# QNAP Configuration
QNAP_HOST="192.168.1.140"
QNAP_USER="CARMENVELASCO\joaquin"
QNAP_SHARE="JOAQUIN"
QNAP_MOUNT_POINT="/Volumes/JOAQUIN"

# Backup Configuration
RETENTION_DAYS=30
```

## 🔧 Volúmenes Gestionados

### MongoDB (7 volúmenes)
- `mongo_mongo1_data` - `mongo_mongo6_data`
- `analiticacontainer_mongo_data`

### Milvus (18 volúmenes)
- `milvus_milvus1_data` - `milvus_milvus5_data`
- `milvus_minio1_data` - `milvus_minio5_data`
- `milvus_etcd1_data` - `milvus_etcd5_data`
- `macrochat_milvus-data`, `macrochat_milvus-etcd-data`, `macrochat_milvus-minio-data`

### PostgreSQL/Redis
- `macrochat_postgres-data`
- `macrochat_redis-data`
- `macrochat_minio-data`

### Adicionales
- `clinica-app_*`
- `infra_*`
- `analiticacontainer_*`

## 📊 Estructura de Backups

```
/Volumes/JOAQUIN/milvus-backups/
├── mongodb/
│   └── mongodb_backup_YYYYMMDD_HHMMSS/
│       ├── mongo_mongo1_data.tar.gz
│       ├── mongo_mongo2_data.tar.gz
│       └── metadata.json
├── volumes/
│   ├── milvus_backup_YYYYMMDD_HHMMSS/
│   │   ├── milvus_milvus1_data.tar.gz
│   │   └── metadata.json
│   └── additional_YYYYMMDD_HHMMSS/
├── postgres/
│   └── postgres_backup_YYYYMMDD_HHMMSS/
├── logs/
│   └── backup_global_YYYYMMDD_HHMMSS.log
└── backup_global_YYYYMMDD_HHMMSS.json
```

## 🔄 Endpoints API

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/status` | Estado del sistema |
| GET | `/api/volumes` | Lista volúmenes Docker |
| GET | `/api/backups` | Lista backups disponibles |
| GET | `/api/backups/{timestamp}` | Detalle de backup |
| POST | `/api/backup/{type}` | Inicia backup (global/mongodb/milvus/postgres) |
| POST | `/api/restore` | Inicia restauración |
| GET | `/api/tasks` | Lista tareas |
| GET | `/api/tasks/{id}` | Estado de tarea |
| POST | `/api/mount-qnap` | Intenta montar QNAP |
| GET | `/api/disk-usage` | Uso de disco QNAP |

### Endpoints de Schedules

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| GET | `/api/schedules` | Lista todos los schedules |
| GET | `/api/schedules/stats` | Estadísticas del scheduler |
| GET | `/api/schedules/presets` | Presets disponibles |
| GET | `/api/schedules/history` | Historial de ejecuciones |
| POST | `/api/schedules` | Crea nuevo schedule |
| POST | `/api/schedules/from-preset/{id}` | Crea desde preset |
| GET | `/api/schedules/{id}` | Obtiene schedule |
| PUT | `/api/schedules/{id}` | Actualiza schedule |
| DELETE | `/api/schedules/{id}` | Elimina schedule |
| POST | `/api/schedules/{id}/pause` | Pausa schedule |
| POST | `/api/schedules/{id}/resume` | Reanuda schedule |
| POST | `/api/schedules/{id}/run-now` | Ejecuta inmediatamente |

## 🛠️ Desarrollo Local

### Backend

```bash
cd backend
pip install -r requirements.txt
QNAP_MOUNT_POINT=/Volumes/JOAQUIN python -m uvicorn main:app --reload --port 8080
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

## 🐛 Troubleshooting

### QNAP no se monta
```bash
# Montar manualmente en macOS
open smb://192.168.1.140/JOAQUIN
```

### Docker no responde
```bash
# Reiniciar Docker Desktop
open -a Docker
```

### Ver logs del contenedor
```bash
docker logs -f qnap-backup-manager
```

## 📝 Licencia

MIT License

---

**Desarrollado para gestionar backups de MongoDB + Milvus en QNAP NAS con programación automática** 🚀
**Desarrollado para gestionar backups de MongoDB + Milvus en QNAP NAS** 🚀
