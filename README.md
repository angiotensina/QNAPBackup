# 🗄️ Database Backup to QNAP

Sistema de backup automatizado para MongoDB, Milvus y PostgreSQL hacia NAS QNAP.

## 📋 Requisitos

- Docker instalado y funcionando
- Python 3.8+ con pip
- Acceso al NAS QNAP (192.168.1.140)
- Share SMB configurado en QNAP

## 🗃️ Bases de Datos Soportadas

| Base de Datos | Tipo | Método de Backup |
|---------------|------|------------------|
| 🍃 MongoDB | NoSQL/Documentos | Volúmenes Docker |
| 🔷 Milvus | Vector DB | Volúmenes Docker |
| 🐘 PostgreSQL | Relacional | pg_dump + Volúmenes |

## 🚀 Configuración Inicial

### 1. Preparar QNAP

1. Accede a la interfaz web del QNAP: `http://192.168.1.140`
2. Crea una carpeta compartida llamada `MilvusBackup`
3. Configura permisos de lectura/escritura para tu usuario

### 2. Configurar credenciales

Edita el archivo `config.env`:

```bash
# Cambiar estos valores según tu configuración
QNAP_USER="tu_usuario"
QNAP_SHARE="MilvusBackup"
```

### 3. Dar permisos de ejecución

```bash
cd /Users/joaquinchamorromohedas/Desktop/QNAPBackup
chmod +x scripts/*.sh
```

### 4. Instalar dependencias Python

```bash
pip install pymilvus numpy
```

## 📦 Uso

### 🚀 Backup Completo de TODAS las Bases de Datos (Recomendado)

```bash
./scripts/backup_all_databases.sh
```

Este script hace backup de:
1. ✅ MongoDB (volúmenes Docker)
2. ✅ Milvus (volúmenes Docker)
3. ✅ PostgreSQL (pg_dump + volúmenes Docker)

### Backup Individual por Base de Datos

```bash
# Solo MongoDB
./scripts/backup_mongodb_docker.sh

# Solo Milvus
./scripts/backup_volumes_docker.sh

# Solo PostgreSQL
./scripts/backup_postgres_docker.sh
```

### Backup Manual Completo (Legacy)

```bash
./scripts/backup_full.sh
```

Este script:
1. ✅ Monta el share QNAP
2. ✅ Hace backup de todos los volúmenes Docker de Milvus
3. ✅ Exporta schemas y metadatos de colecciones

### Solo Backup de Volúmenes

```bash
./scripts/mount_qnap.sh
./scripts/backup_volumes.sh
```

### Solo Backup de Colecciones

```bash
python3 scripts/backup_collections.py
```

### Restaurar desde Backup

```bash
./scripts/restore_volumes.sh
```

⚠️ **Advertencia**: La restauración sobrescribirá los datos actuales.

## ⏰ Backup Automático

Configurar backup programado con cron:

```bash
./scripts/setup_cron.sh
```

Opciones disponibles:
- Diario a las 2:00 AM
- Cada 6 horas
- Semanal (Domingos)
- Horario personalizado

## 📁 Estructura de Backup

```
/Volumes/JOAQUIN/milvus-backups/
├── mongodb/
│   └── mongodb_backup_20241231_143000/
│       ├── mongo_mongo1_data.tar.gz
│       ├── mongo_mongo2_data.tar.gz
│       └── metadata.json
├── volumes/
│   └── milvus_backup_20241231_143000/
│       ├── milvus_milvus1_data.tar.gz
│       ├── milvus_minio1_data.tar.gz
│       ├── milvus_etcd1_data.tar.gz
│       └── metadata.json
├── postgres/
│   └── postgres_backup_20241231_143000/
│       ├── dumps/
│       │   ├── postgres-gdash_all_databases.sql.gz
│       │   ├── macrochat-postgres_all_databases.sql.gz
│       │   └── ...
│       ├── volumes/
│       │   ├── macrochat_postgres-data.tar.gz
│       │   ├── agents-postgres-data.tar.gz
│       │   └── ...
│       └── metadata.json
├── collections/
│   └── backup_20241231_143000/
│       ├── milvus-1/
│       │   ├── collection_name_schema.json
│       │   └── collection_name_info.json
│       └── backup_summary.json
└── logs/
    └── backup_20241231_143000.log
```

## 🔧 Instancias Milvus Detectadas

| Instancia | Puerto | Estado |
|-----------|--------|--------|
| milvus-standalone-1 | 19530 | ✅ Activo |
| milvus-standalone-2 | 19531 | ✅ Activo |
| milvus-standalone-3 | 19532 | ✅ Activo |
| milvus-standalone-4 | 19533 | ✅ Activo |
| milvus-standalone-5 | 19534 | ✅ Activo |
| macrochat-milvus | 19540 | ✅ Activo |

## 🐘 Instancias PostgreSQL Detectadas

| Contenedor | Imagen | Volumen |
|------------|--------|---------|
| postgres-gdash | postgres:17 | - |
| medimecum-postgres | postgres:16-alpine | - |
| usreaderplus-db | postgres:16-alpine | usreaderplus_postgres_data |
| macrochat-postgres | pgvector/pgvector:pg16 | macrochat_postgres-data |
| postgres_graph_clinical | postgres:16-alpine | graph-gpt-5_postgres_graph_clinical_data |
| agents-postgres | postgres:16-alpine | agents-postgres-data |
| pgvector-container | pgvector/pgvector:pg16 | pgvector_data |
| postgres_db1-5 | postgres:latest | postgres_db*_data |

## 🔄 Estrategias de Backup

### 1. Backup de Volúmenes (Recomendado)
- **Pros**: Backup completo, incluye todos los datos
- **Contras**: Mayor tamaño, requiere detener servicios para restaurar
- **Uso**: Disaster recovery completo

### 2. Backup de Colecciones
- **Pros**: Backup granular, schemas exportables
- **Contras**: No incluye vectores completos
- **Uso**: Documentación, migración de schemas

### 3. milvus-backup (Oficial)
Para backups de nivel enterprise, considera usar la herramienta oficial:
```bash
# Instalación
git clone https://github.com/zilliztech/milvus-backup.git
cd milvus-backup
go build

# Uso
./milvus-backup create -n my_backup
./milvus-backup list
./milvus-backup restore -n my_backup
```

## 🛠️ Troubleshooting

### Error: QNAP no se monta
```bash
# Montar manualmente
open smb://192.168.1.140/MilvusBackup
```

### Error: Permiso denegado
```bash
# Verificar permisos en QNAP
# Asegúrate de que el usuario tiene acceso RW al share
```

### Error: Volumen no existe
```bash
# Listar volúmenes disponibles
docker volume ls | grep milvus
```

## 📝 Logs

Los logs se guardan en:
- Local: `./logs/`
- QNAP: `/Volumes/QNAPBackup/milvus-backups/logs/`

## 🔐 Seguridad

- Los backups contienen datos sensibles
- Configura permisos restrictivos en el share QNAP
- Considera encriptar los backups para datos críticos

## 📞 Soporte

Para problemas específicos de Milvus:
- [Documentación oficial](https://milvus.io/docs)
- [GitHub Issues](https://github.com/milvus-io/milvus/issues)
