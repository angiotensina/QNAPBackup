"""
QNAP Backup Manager - Backend API
FastAPI application for managing Docker volume backups to QNAP NAS
"""

import os
import json
import asyncio
import subprocess
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
from enum import Enum
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings

from backend.scheduler import (
    BackupScheduler, ScheduleConfig, ScheduleType, ScheduleStatus,
    SCHEDULE_PRESETS
)

# Configurar logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Settings(BaseSettings):
    """Application settings"""
    QNAP_HOST: str = "192.168.1.140"
    QNAP_SHARE: str = "JOAQUIN"
    QNAP_MOUNT_POINT: str = "/Volumes/JOAQUIN"
    QNAP_USER: str = "CARMENVELASCO\\joaquin"
    SCRIPTS_DIR: str = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts')
    BACKUP_BASE: str = "/Volumes/JOAQUIN/milvus-backups"
    
    model_config = {
        "env_file": ".env",
        "extra": "ignore"  # Ignorar campos extra del .env
    }


settings = Settings()

# Inicializar scheduler global
backup_scheduler: Optional[BackupScheduler] = None


async def scheduled_backup_callback(backup_type: str, schedule_id: str):
    """Callback para ejecutar backups desde el scheduler"""
    task_id = f"scheduled_{backup_type}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    backup_tasks[task_id] = {
        "task_id": task_id,
        "backup_type": backup_type,
        "status": BackupStatus.PENDING,
        "started_at": datetime.now().isoformat(),
        "completed_at": None,
        "output": [f"🕐 Backup programado iniciado (schedule: {schedule_id})"],
        "error": None,
        "scheduled": True,
        "schedule_id": schedule_id
    }
    
    await run_backup_script(task_id, BackupType(backup_type))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle manager para iniciar/detener el scheduler"""
    global backup_scheduler
    
    # Startup
    import os
    data_dir = os.environ.get('DATA_DIR', os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data'))
    os.makedirs(data_dir, exist_ok=True)
    backup_scheduler = BackupScheduler(
        config_file=os.path.join(data_dir, 'schedules.json'),
        backup_callback=scheduled_backup_callback
    )
    backup_scheduler.start()
    logger.info("🚀 Backup Scheduler iniciado")
    
    yield
    
    # Shutdown
    if backup_scheduler:
        backup_scheduler.stop()
        logger.info("🛑 Backup Scheduler detenido")


app = FastAPI(
    title="QNAP Backup Manager",
    description="API para gestionar backups de Docker volumes en QNAP NAS",
    version="2.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Estado global de tareas
backup_tasks: Dict[str, Dict[str, Any]] = {}


# ============================================
# Models
# ============================================

class BackupType(str, Enum):
    MONGODB = "mongodb"
    MILVUS = "milvus"
    POSTGRES = "postgres"
    ADDITIONAL = "additional"
    GLOBAL = "global"


class BackupStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class BackupInfo(BaseModel):
    """Información de un backup"""
    timestamp: str
    backup_type: str
    path: str
    size: Optional[str] = None
    date: str
    components: Optional[Dict[str, Any]] = None


class BackupTask(BaseModel):
    """Estado de una tarea de backup"""
    task_id: str
    backup_type: BackupType
    status: BackupStatus
    started_at: str
    completed_at: Optional[str] = None
    output: List[str] = []
    error: Optional[str] = None


class SystemStatus(BaseModel):
    """Estado del sistema"""
    docker_running: bool
    qnap_mounted: bool
    qnap_path: str
    backup_base: str
    total_backups: int
    last_backup: Optional[str] = None
    docker_volumes: int
    running_containers: int


class VolumeInfo(BaseModel):
    """Información de un volumen Docker"""
    name: str
    driver: str
    size: Optional[str] = None
    category: str  # mongodb, milvus, postgres, other


class RestoreRequest(BaseModel):
    """Solicitud de restauración"""
    timestamp: str
    components: List[str] = Field(default=["mongodb", "milvus", "postgres", "additional"])


# ============================================
# Schedule Models (Pydantic)
# ============================================

class ScheduleCreateRequest(BaseModel):
    """Solicitud de creación de schedule"""
    name: str = Field(..., min_length=1, max_length=100)
    description: str = Field(default="", max_length=500)
    backup_types: List[str] = Field(..., min_items=1)
    schedule_type: str = Field(..., description="cron, interval, daily, weekly, monthly, once")
    
    # Campos opcionales según tipo
    cron_expression: Optional[str] = None
    interval_minutes: Optional[int] = Field(None, ge=5, le=10080)  # 5min - 1 semana
    time_of_day: Optional[str] = Field(None, pattern=r"^\d{2}:\d{2}$")
    days_of_week: Optional[List[int]] = None  # 0=Lunes, 6=Domingo
    days_of_month: Optional[List[int]] = None
    run_date: Optional[str] = None
    
    # Opciones avanzadas
    sequential_execution: bool = True
    retry_on_failure: bool = True
    max_retries: int = Field(default=3, ge=0, le=10)


class ScheduleUpdateRequest(BaseModel):
    """Solicitud de actualización de schedule"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    backup_types: Optional[List[str]] = None
    schedule_type: Optional[str] = None
    status: Optional[str] = None  # active, paused, disabled
    
    cron_expression: Optional[str] = None
    interval_minutes: Optional[int] = None
    time_of_day: Optional[str] = None
    days_of_week: Optional[List[int]] = None
    days_of_month: Optional[List[int]] = None
    run_date: Optional[str] = None
    
    sequential_execution: Optional[bool] = None
    retry_on_failure: Optional[bool] = None
    max_retries: Optional[int] = None


class ScheduleResponse(BaseModel):
    """Respuesta con información de schedule"""
    id: str
    name: str
    description: str
    backup_types: List[str]
    schedule_type: str
    status: str
    cron_expression: Optional[str] = None
    interval_minutes: Optional[int] = None
    time_of_day: Optional[str] = None
    days_of_week: Optional[List[int]] = None
    days_of_month: Optional[List[int]] = None
    run_date: Optional[str] = None
    created_at: str
    updated_at: str
    last_run: Optional[str] = None
    next_run: Optional[str] = None
    run_count: int
    last_status: Optional[str] = None
    sequential_execution: bool
    retry_on_failure: bool
    max_retries: int


# ============================================
# Utility Functions
# ============================================

def run_command(cmd: str, capture_output: bool = True) -> tuple[int, str, str]:
    """Ejecuta un comando shell"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=capture_output,
            text=True,
            timeout=600
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)


def check_docker() -> bool:
    """Verifica si Docker está corriendo"""
    code, _, _ = run_command("docker info > /dev/null 2>&1")
    return code == 0


def check_qnap_mounted() -> bool:
    """Verifica si QNAP está montado"""
    return os.path.isdir(settings.QNAP_MOUNT_POINT) and os.access(settings.QNAP_MOUNT_POINT, os.W_OK)


def get_docker_volumes() -> List[VolumeInfo]:
    """Obtiene lista de volúmenes Docker"""
    code, stdout, _ = run_command("docker volume ls --format '{{.Name}}|{{.Driver}}'")
    if code != 0:
        return []
    
    volumes = []
    for line in stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split('|')
        name = parts[0]
        driver = parts[1] if len(parts) > 1 else "local"
        
        # Categorizar
        if 'mongo' in name.lower():
            category = 'mongodb'
        elif 'milvus' in name.lower() or 'minio' in name.lower() or 'etcd' in name.lower():
            category = 'milvus'
        elif 'postgres' in name.lower():
            category = 'postgres'
        elif 'redis' in name.lower():
            category = 'redis'
        else:
            category = 'other'
        
        volumes.append(VolumeInfo(name=name, driver=driver, category=category))
    
    return volumes


def get_running_containers() -> int:
    """Cuenta contenedores corriendo"""
    code, stdout, _ = run_command("docker ps -q | wc -l")
    if code != 0:
        return 0
    return int(stdout.strip()) if stdout.strip() else 0


def get_backups_list() -> List[BackupInfo]:
    """Obtiene lista de backups disponibles"""
    backups = []
    backup_base = Path(settings.BACKUP_BASE)
    
    if not backup_base.exists():
        return backups
    
    # Buscar archivos JSON de backup global
    for json_file in backup_base.glob("backup_global_*.json"):
        try:
            with open(json_file) as f:
                data = json.load(f)
            
            timestamp = json_file.stem.replace("backup_global_", "")
            backups.append(BackupInfo(
                timestamp=timestamp,
                backup_type="global",
                path=str(json_file),
                date=data.get("backup_date_local", ""),
                components=data.get("components", {})
            ))
        except Exception:
            continue
    
    # Ordenar por timestamp descendente
    backups.sort(key=lambda x: x.timestamp, reverse=True)
    return backups


def get_backup_size(path: str) -> str:
    """Obtiene tamaño de un directorio"""
    code, stdout, _ = run_command(f"du -sh '{path}' 2>/dev/null | cut -f1")
    return stdout.strip() if code == 0 else "N/A"


# ============================================
# Background Tasks
# ============================================

async def run_backup_script(task_id: str, backup_type: BackupType):
    """Ejecuta script de backup en background"""
    task = backup_tasks[task_id]
    task["status"] = BackupStatus.RUNNING
    
    script_map = {
        BackupType.MONGODB: "backup_mongodb_docker.sh",
        BackupType.MILVUS: "backup_volumes_docker.sh",
        BackupType.POSTGRES: "backup_postgres_docker.sh",
        BackupType.GLOBAL: "backup_global.sh",
    }
    
    script_name = script_map.get(backup_type, "backup_global.sh")
    script_path = f"{settings.SCRIPTS_DIR}/{script_name}"
    
    # Ejecutar en Docker si estamos en contenedor, o directamente si estamos en host
    if os.path.exists("/app/scripts"):
        cmd = f"QNAP_MOUNT_POINT={settings.QNAP_MOUNT_POINT} bash {script_path}"
    else:
        # Estamos en el host
        script_path = os.path.join(os.path.dirname(__file__), "..", "scripts", script_name)
        cmd = f"QNAP_MOUNT_POINT={settings.QNAP_MOUNT_POINT} bash {script_path}"
    
    try:
        process = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env={**os.environ, "QNAP_MOUNT_POINT": settings.QNAP_MOUNT_POINT}
        )
        
        while True:
            line = await process.stdout.readline()
            if not line:
                break
            decoded = line.decode().strip()
            if decoded:
                task["output"].append(decoded)
        
        await process.wait()
        
        if process.returncode == 0:
            task["status"] = BackupStatus.COMPLETED
        else:
            task["status"] = BackupStatus.FAILED
            task["error"] = f"Exit code: {process.returncode}"
            
    except Exception as e:
        task["status"] = BackupStatus.FAILED
        task["error"] = str(e)
    
    task["completed_at"] = datetime.now().isoformat()


async def run_restore_script(task_id: str, timestamp: str, components: List[str]):
    """Ejecuta restauración en background"""
    task = backup_tasks[task_id]
    task["status"] = BackupStatus.RUNNING
    
    backup_base = settings.BACKUP_BASE
    
    try:
        for component in components:
            task["output"].append(f"🔄 Restaurando {component}...")
            
            if component == "mongodb":
                backup_path = f"{backup_base}/mongodb/mongodb_backup_{timestamp}"
            elif component == "milvus":
                backup_path = f"{backup_base}/volumes/milvus_backup_{timestamp}"
            elif component == "postgres":
                backup_path = f"{backup_base}/postgres/postgres_backup_{timestamp}"
            elif component == "additional":
                backup_path = f"{backup_base}/volumes/additional_{timestamp}"
            else:
                continue
            
            if not os.path.isdir(backup_path):
                task["output"].append(f"⚠️ No se encontró backup de {component} para {timestamp}")
                continue
            
            # Detectar subdirectorio volumes/ (nuevo formato de backup)
            actual_path = backup_path
            volumes_subdir = Path(backup_path) / "volumes"
            if volumes_subdir.is_dir():
                actual_path = str(volumes_subdir)
                task["output"].append(f"   📁 Usando subdirectorio volumes/")
            
            # Restaurar cada volumen
            for tar_file in Path(actual_path).glob("*.tar.gz"):
                vol_name = tar_file.stem.replace(".tar", "")
                
                # Crear volumen
                await asyncio.create_subprocess_shell(
                    f"docker volume create {vol_name}",
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL
                )
                
                # Restaurar usando actual_path que puede ser el subdirectorio volumes/
                cmd = f"docker run --rm -v {vol_name}:/target -v {actual_path}:/backup:ro alpine:latest sh -c 'tar -xzf /backup/{tar_file.name} -C /target'"
                process = await asyncio.create_subprocess_shell(
                    cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                await process.wait()
                
                if process.returncode == 0:
                    task["output"].append(f"   ✅ {vol_name}")
                else:
                    task["output"].append(f"   ❌ {vol_name}")
            
            task["output"].append(f"✅ {component} restaurado")
        
        task["status"] = BackupStatus.COMPLETED
        
    except Exception as e:
        task["status"] = BackupStatus.FAILED
        task["error"] = str(e)
    
    task["completed_at"] = datetime.now().isoformat()


# ============================================
# API Endpoints
# ============================================

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "ok", "timestamp": datetime.now().isoformat()}


@app.get("/api/status", response_model=SystemStatus)
async def get_system_status():
    """Obtiene estado del sistema"""
    docker_running = check_docker()
    qnap_mounted = check_qnap_mounted()
    volumes = get_docker_volumes() if docker_running else []
    containers = get_running_containers() if docker_running else 0
    backups = get_backups_list() if qnap_mounted else []
    
    return SystemStatus(
        docker_running=docker_running,
        qnap_mounted=qnap_mounted,
        qnap_path=settings.QNAP_MOUNT_POINT,
        backup_base=settings.BACKUP_BASE,
        total_backups=len(backups),
        last_backup=backups[0].timestamp if backups else None,
        docker_volumes=len(volumes),
        running_containers=containers
    )


@app.get("/api/volumes", response_model=List[VolumeInfo])
async def list_volumes():
    """Lista volúmenes Docker"""
    if not check_docker():
        raise HTTPException(status_code=503, detail="Docker no está corriendo")
    return get_docker_volumes()


@app.get("/api/backups", response_model=List[BackupInfo])
async def list_backups():
    """Lista backups disponibles"""
    if not check_qnap_mounted():
        raise HTTPException(status_code=503, detail="QNAP no está montado")
    return get_backups_list()


@app.get("/api/backups/{timestamp}")
async def get_backup_detail(timestamp: str):
    """Obtiene detalle de un backup específico"""
    json_path = Path(settings.BACKUP_BASE) / f"backup_global_{timestamp}.json"
    
    if not json_path.exists():
        raise HTTPException(status_code=404, detail="Backup no encontrado")
    
    with open(json_path) as f:
        data = json.load(f)
    
    # Agregar tamaños actuales
    for key, comp in data.get("components", {}).items():
        if "path" in comp:
            full_path = Path(settings.BACKUP_BASE) / comp["path"]
            if full_path.exists():
                comp["current_size"] = get_backup_size(str(full_path))
    
    return data


@app.post("/api/backup/{backup_type}")
async def start_backup(backup_type: BackupType, background_tasks: BackgroundTasks):
    """Inicia un backup"""
    if not check_docker():
        raise HTTPException(status_code=503, detail="Docker no está corriendo")
    if not check_qnap_mounted():
        raise HTTPException(status_code=503, detail="QNAP no está montado")
    
    task_id = f"backup_{backup_type.value}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    backup_tasks[task_id] = {
        "task_id": task_id,
        "backup_type": backup_type,
        "status": BackupStatus.PENDING,
        "started_at": datetime.now().isoformat(),
        "completed_at": None,
        "output": [],
        "error": None
    }
    
    background_tasks.add_task(run_backup_script, task_id, backup_type)
    
    return {"task_id": task_id, "message": f"Backup {backup_type.value} iniciado"}


@app.post("/api/restore")
async def start_restore(request: RestoreRequest, background_tasks: BackgroundTasks):
    """Inicia una restauración"""
    if not check_docker():
        raise HTTPException(status_code=503, detail="Docker no está corriendo")
    if not check_qnap_mounted():
        raise HTTPException(status_code=503, detail="QNAP no está montado")
    
    task_id = f"restore_{request.timestamp}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    backup_tasks[task_id] = {
        "task_id": task_id,
        "backup_type": "restore",
        "status": BackupStatus.PENDING,
        "started_at": datetime.now().isoformat(),
        "completed_at": None,
        "output": [],
        "error": None
    }
    
    background_tasks.add_task(run_restore_script, task_id, request.timestamp, request.components)
    
    return {"task_id": task_id, "message": f"Restauración iniciada para {request.timestamp}"}


@app.get("/api/tasks/{task_id}")
async def get_task_status(task_id: str):
    """Obtiene estado de una tarea"""
    if task_id not in backup_tasks:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
    return backup_tasks[task_id]


@app.get("/api/tasks")
async def list_tasks():
    """Lista todas las tareas"""
    return list(backup_tasks.values())


@app.post("/api/mount-qnap")
async def mount_qnap():
    """Intenta montar el QNAP"""
    if check_qnap_mounted():
        return {"status": "already_mounted", "path": settings.QNAP_MOUNT_POINT}
    
    # Intentar abrir en Finder (macOS)
    code, _, _ = run_command(f"open 'smb://{settings.QNAP_HOST}/{settings.QNAP_SHARE}'")
    
    # Esperar un poco
    await asyncio.sleep(3)
    
    if check_qnap_mounted():
        return {"status": "mounted", "path": settings.QNAP_MOUNT_POINT}
    
    raise HTTPException(
        status_code=503, 
        detail=f"No se pudo montar. Por favor monta manualmente: smb://{settings.QNAP_HOST}/{settings.QNAP_SHARE}"
    )


@app.get("/api/logs/{timestamp}")
async def get_backup_logs(timestamp: str):
    """Obtiene logs de un backup"""
    log_patterns = [
        f"backup_global_{timestamp}.log",
        f"mongodb_{timestamp}.log",
        f"milvus_{timestamp}.log"
    ]
    
    logs_dir = Path(settings.BACKUP_BASE) / "logs"
    logs_content = {}
    
    for pattern in log_patterns:
        log_file = logs_dir / pattern
        if log_file.exists():
            with open(log_file) as f:
                logs_content[pattern] = f.read()
    
    if not logs_content:
        raise HTTPException(status_code=404, detail="No se encontraron logs")
    
    return logs_content


@app.get("/api/disk-usage")
async def get_disk_usage():
    """Obtiene uso de disco del QNAP"""
    if not check_qnap_mounted():
        raise HTTPException(status_code=503, detail="QNAP no está montado")
    
    code, stdout, _ = run_command(f"df -h '{settings.QNAP_MOUNT_POINT}' | tail -1")
    if code != 0:
        raise HTTPException(status_code=500, detail="Error obteniendo uso de disco")
    
    parts = stdout.split()
    if len(parts) >= 5:
        return {
            "total": parts[1],
            "used": parts[2],
            "available": parts[3],
            "percent_used": parts[4],
            "mount_point": settings.QNAP_MOUNT_POINT
        }
    
    return {"raw": stdout}


# ============================================
# Schedule Endpoints
# ============================================

def schedule_to_response(schedule: ScheduleConfig) -> ScheduleResponse:
    """Convierte ScheduleConfig a ScheduleResponse"""
    return ScheduleResponse(
        id=schedule.id,
        name=schedule.name,
        description=schedule.description,
        backup_types=schedule.backup_types,
        schedule_type=schedule.schedule_type.value,
        status=schedule.status.value,
        cron_expression=schedule.cron_expression,
        interval_minutes=schedule.interval_minutes,
        time_of_day=schedule.time_of_day,
        days_of_week=schedule.days_of_week,
        days_of_month=schedule.days_of_month,
        run_date=schedule.run_date,
        created_at=schedule.created_at,
        updated_at=schedule.updated_at,
        last_run=schedule.last_run,
        next_run=schedule.next_run,
        run_count=schedule.run_count,
        last_status=schedule.last_status,
        sequential_execution=schedule.sequential_execution,
        retry_on_failure=schedule.retry_on_failure,
        max_retries=schedule.max_retries
    )


@app.get("/api/schedules", response_model=List[ScheduleResponse])
async def list_schedules():
    """Lista todos los schedules de backup"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    schedules = backup_scheduler.get_all_schedules()
    return [schedule_to_response(s) for s in schedules]


@app.get("/api/schedules/stats")
async def get_scheduler_stats():
    """Obtiene estadísticas del scheduler"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    return backup_scheduler.get_stats()


@app.get("/api/schedules/presets")
async def get_schedule_presets():
    """Obtiene presets de schedules predefinidos"""
    return {
        'presets': [
            {
                'id': key,
                **{k: v.value if hasattr(v, 'value') else v for k, v in preset.items()}
            }
            for key, preset in SCHEDULE_PRESETS.items()
        ]
    }


@app.get("/api/schedules/history")
async def get_schedule_history(schedule_id: Optional[str] = None, limit: int = 20):
    """Obtiene historial de ejecuciones de schedules"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    return {"history": backup_scheduler.get_history(schedule_id, limit)}


@app.post("/api/schedules", response_model=ScheduleResponse)
async def create_schedule(request: ScheduleCreateRequest):
    """Crea un nuevo schedule de backup"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    # Validar backup_types
    valid_types = {'mongodb', 'milvus', 'postgres', 'additional', 'global'}
    for bt in request.backup_types:
        if bt not in valid_types:
            raise HTTPException(status_code=400, detail=f"Tipo de backup inválido: {bt}")
    
    # Validar configuración según tipo
    if request.schedule_type == 'cron' and not request.cron_expression:
        raise HTTPException(status_code=400, detail="Se requiere cron_expression para tipo cron")
    if request.schedule_type == 'interval' and not request.interval_minutes:
        raise HTTPException(status_code=400, detail="Se requiere interval_minutes para tipo interval")
    if request.schedule_type in ['daily', 'weekly', 'monthly'] and not request.time_of_day:
        raise HTTPException(status_code=400, detail=f"Se requiere time_of_day para tipo {request.schedule_type}")
    if request.schedule_type == 'weekly' and not request.days_of_week:
        raise HTTPException(status_code=400, detail="Se requiere days_of_week para tipo weekly")
    if request.schedule_type == 'monthly' and not request.days_of_month:
        raise HTTPException(status_code=400, detail="Se requiere days_of_month para tipo monthly")
    if request.schedule_type == 'once' and not request.run_date:
        raise HTTPException(status_code=400, detail="Se requiere run_date para tipo once")
    
    try:
        schedule = backup_scheduler.create_schedule(request.model_dump())
        return schedule_to_response(schedule)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/schedules/from-preset/{preset_id}", response_model=ScheduleResponse)
async def create_from_preset(preset_id: str):
    """Crea un schedule desde un preset predefinido"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    if preset_id not in SCHEDULE_PRESETS:
        raise HTTPException(status_code=404, detail=f"Preset no encontrado: {preset_id}")
    
    preset = SCHEDULE_PRESETS[preset_id].copy()
    schedule = backup_scheduler.create_schedule(preset)
    return schedule_to_response(schedule)


@app.get("/api/schedules/{schedule_id}", response_model=ScheduleResponse)
async def get_schedule(schedule_id: str):
    """Obtiene un schedule por ID"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    schedule = backup_scheduler.get_schedule(schedule_id)
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return schedule_to_response(schedule)


@app.put("/api/schedules/{schedule_id}", response_model=ScheduleResponse)
async def update_schedule(schedule_id: str, request: ScheduleUpdateRequest):
    """Actualiza un schedule existente"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    updates = {k: v for k, v in request.model_dump().items() if v is not None}
    schedule = backup_scheduler.update_schedule(schedule_id, updates)
    
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return schedule_to_response(schedule)


@app.delete("/api/schedules/{schedule_id}")
async def delete_schedule(schedule_id: str):
    """Elimina un schedule"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    if not backup_scheduler.delete_schedule(schedule_id):
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return {"status": "deleted", "schedule_id": schedule_id}


@app.post("/api/schedules/{schedule_id}/pause")
async def pause_schedule(schedule_id: str):
    """Pausa un schedule"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    schedule = backup_scheduler.pause_schedule(schedule_id)
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return {"status": "paused", "schedule_id": schedule_id}


@app.post("/api/schedules/{schedule_id}/resume")
async def resume_schedule(schedule_id: str):
    """Reanuda un schedule pausado"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    schedule = backup_scheduler.resume_schedule(schedule_id)
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return {"status": "resumed", "schedule_id": schedule_id}


@app.post("/api/schedules/{schedule_id}/run-now")
async def run_schedule_now(schedule_id: str):
    """Ejecuta un schedule inmediatamente"""
    if not backup_scheduler:
        raise HTTPException(status_code=503, detail="Scheduler no inicializado")
    
    if not check_qnap_mounted():
        raise HTTPException(status_code=503, detail="QNAP no está montado")
    
    if not backup_scheduler.run_now(schedule_id):
        raise HTTPException(status_code=404, detail="Schedule no encontrado")
    
    return {"status": "started", "schedule_id": schedule_id, "message": "Backup iniciado"}


# ============================================
# Static Files & SPA Fallback
# ============================================

# Mount static files if directory exists
static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/assets", StaticFiles(directory=str(static_dir / "assets")), name="assets")
    
    @app.get("/favicon.svg")
    async def favicon():
        return FileResponse(str(static_dir / "favicon.svg"))
    
    @app.get("/{full_path:path}")
    async def serve_spa(request: Request, full_path: str):
        """Serve SPA for all non-API routes"""
        if full_path.startswith("api"):
            raise HTTPException(status_code=404)
        index_file = static_dir / "index.html"
        if index_file.exists():
            return FileResponse(str(index_file))
        raise HTTPException(status_code=404)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=6640)
