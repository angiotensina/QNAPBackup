"""
QNAP Backup Manager - Scheduler Module
Sistema de programación de backups con APScheduler
"""

import os
import json
import asyncio
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any, Callable
from enum import Enum
from dataclasses import dataclass, asdict, field
from uuid import uuid4

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.date import DateTrigger
from apscheduler.jobstores.memory import MemoryJobStore
from croniter import croniter

logger = logging.getLogger(__name__)


class ScheduleType(str, Enum):
    """Tipos de programación"""
    CRON = "cron"           # Expresión cron (más flexible)
    INTERVAL = "interval"   # Cada N minutos/horas/días
    DAILY = "daily"         # Diario a una hora específica
    WEEKLY = "weekly"       # Semanal en días específicos
    MONTHLY = "monthly"     # Mensual en días específicos
    ONCE = "once"           # Una sola vez


class ScheduleStatus(str, Enum):
    """Estados de schedule"""
    ACTIVE = "active"
    PAUSED = "paused"
    DISABLED = "disabled"


@dataclass
class ScheduleConfig:
    """Configuración de un schedule de backup"""
    id: str
    name: str
    description: str
    backup_types: List[str]  # Lista de tipos: mongodb, milvus, postgres, additional, global
    schedule_type: ScheduleType
    status: ScheduleStatus = ScheduleStatus.ACTIVE
    
    # Configuración según tipo
    cron_expression: Optional[str] = None  # Para CRON: "0 2 * * *"
    interval_minutes: Optional[int] = None  # Para INTERVAL
    time_of_day: Optional[str] = None       # Para DAILY/WEEKLY/MONTHLY: "02:00"
    days_of_week: Optional[List[int]] = None  # Para WEEKLY: [0,1,2,3,4] (L-V)
    days_of_month: Optional[List[int]] = None  # Para MONTHLY: [1, 15]
    run_date: Optional[str] = None          # Para ONCE: "2026-01-10 02:00:00"
    
    # Metadatos
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now().isoformat())
    last_run: Optional[str] = None
    next_run: Optional[str] = None
    run_count: int = 0
    last_status: Optional[str] = None
    
    # Opciones avanzadas
    retry_on_failure: bool = True
    max_retries: int = 3
    notification_email: Optional[str] = None
    sequential_execution: bool = True  # Ejecutar tipos de backup secuencialmente
    
    def to_dict(self) -> Dict[str, Any]:
        """Convierte a diccionario"""
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'ScheduleConfig':
        """Crea desde diccionario"""
        # Convertir enums
        if isinstance(data.get('schedule_type'), str):
            data['schedule_type'] = ScheduleType(data['schedule_type'])
        if isinstance(data.get('status'), str):
            data['status'] = ScheduleStatus(data['status'])
        return cls(**data)


class ScheduleHistory:
    """Historial de ejecuciones de schedules"""
    
    def __init__(self, max_entries: int = 100):
        self.max_entries = max_entries
        self.entries: List[Dict[str, Any]] = []
    
    def add(self, schedule_id: str, schedule_name: str, backup_types: List[str], 
            status: str, duration_seconds: float, message: str = ""):
        """Añade entrada al historial"""
        entry = {
            "id": str(uuid4())[:8],
            "schedule_id": schedule_id,
            "schedule_name": schedule_name,
            "backup_types": backup_types,
            "status": status,
            "duration_seconds": duration_seconds,
            "message": message,
            "timestamp": datetime.now().isoformat()
        }
        self.entries.insert(0, entry)
        # Mantener máximo de entradas
        if len(self.entries) > self.max_entries:
            self.entries = self.entries[:self.max_entries]
    
    def get_recent(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Obtiene entradas recientes"""
        return self.entries[:limit]
    
    def get_by_schedule(self, schedule_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Obtiene historial de un schedule específico"""
        return [e for e in self.entries if e["schedule_id"] == schedule_id][:limit]


class BackupScheduler:
    """Gestor principal de schedules de backup"""
    
    def __init__(self, config_file: str = "/app/data/schedules.json", 
                 backup_callback: Optional[Callable] = None):
        self.config_file = Path(config_file)
        self.backup_callback = backup_callback
        self.schedules: Dict[str, ScheduleConfig] = {}
        self.scheduler = AsyncIOScheduler(
            jobstores={'default': MemoryJobStore()},
            job_defaults={
                'coalesce': True,
                'max_instances': 1,
                'misfire_grace_time': 3600
            }
        )
        self.history = ScheduleHistory()
        self._running_backup = False
        
        # Crear directorio si no existe
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Cargar schedules existentes
        self._load_schedules()
    
    def _load_schedules(self):
        """Carga schedules desde archivo"""
        if self.config_file.exists():
            try:
                with open(self.config_file) as f:
                    data = json.load(f)
                for schedule_data in data.get('schedules', []):
                    schedule = ScheduleConfig.from_dict(schedule_data)
                    self.schedules[schedule.id] = schedule
                logger.info(f"Cargados {len(self.schedules)} schedules")
            except Exception as e:
                logger.error(f"Error cargando schedules: {e}")
    
    def _save_schedules(self):
        """Guarda schedules a archivo"""
        try:
            data = {
                'schedules': [s.to_dict() for s in self.schedules.values()],
                'updated_at': datetime.now().isoformat()
            }
            with open(self.config_file, 'w') as f:
                json.dump(data, f, indent=2, default=str)
            logger.info("Schedules guardados")
        except Exception as e:
            logger.error(f"Error guardando schedules: {e}")
    
    def _get_trigger(self, schedule: ScheduleConfig):
        """Crea trigger de APScheduler según configuración"""
        if schedule.schedule_type == ScheduleType.CRON:
            return CronTrigger.from_crontab(schedule.cron_expression)
        
        elif schedule.schedule_type == ScheduleType.INTERVAL:
            return IntervalTrigger(minutes=schedule.interval_minutes)
        
        elif schedule.schedule_type == ScheduleType.DAILY:
            hour, minute = map(int, schedule.time_of_day.split(':'))
            return CronTrigger(hour=hour, minute=minute)
        
        elif schedule.schedule_type == ScheduleType.WEEKLY:
            hour, minute = map(int, schedule.time_of_day.split(':'))
            days = ','.join(str(d) for d in schedule.days_of_week)
            return CronTrigger(day_of_week=days, hour=hour, minute=minute)
        
        elif schedule.schedule_type == ScheduleType.MONTHLY:
            hour, minute = map(int, schedule.time_of_day.split(':'))
            days = ','.join(str(d) for d in schedule.days_of_month)
            return CronTrigger(day=days, hour=hour, minute=minute)
        
        elif schedule.schedule_type == ScheduleType.ONCE:
            run_date = datetime.fromisoformat(schedule.run_date)
            return DateTrigger(run_date=run_date)
        
        raise ValueError(f"Tipo de schedule no soportado: {schedule.schedule_type}")
    
    def _calculate_next_run(self, schedule: ScheduleConfig) -> Optional[str]:
        """Calcula próxima ejecución"""
        try:
            if schedule.schedule_type == ScheduleType.CRON:
                cron = croniter(schedule.cron_expression, datetime.now())
                return cron.get_next(datetime).isoformat()
            elif schedule.schedule_type == ScheduleType.ONCE:
                return schedule.run_date
            else:
                trigger = self._get_trigger(schedule)
                next_time = trigger.get_next_fire_time(None, datetime.now())
                return next_time.isoformat() if next_time else None
        except Exception as e:
            logger.error(f"Error calculando next_run: {e}")
            return None
    
    async def _execute_scheduled_backup(self, schedule_id: str):
        """Ejecuta backup programado"""
        if schedule_id not in self.schedules:
            logger.error(f"Schedule {schedule_id} no encontrado")
            return
        
        schedule = self.schedules[schedule_id]
        
        if schedule.status != ScheduleStatus.ACTIVE:
            logger.info(f"Schedule {schedule.name} no está activo, saltando")
            return
        
        if self._running_backup:
            logger.warning(f"Ya hay un backup en ejecución, encolando {schedule.name}")
            # Podríamos encolar, por ahora solo logueamos
            return
        
        self._running_backup = True
        start_time = datetime.now()
        
        logger.info(f"🕐 Ejecutando backup programado: {schedule.name}")
        
        try:
            # Ejecutar cada tipo de backup secuencialmente o en paralelo
            if schedule.sequential_execution:
                for backup_type in schedule.backup_types:
                    if self.backup_callback:
                        await self.backup_callback(backup_type, schedule_id)
            else:
                # En paralelo (si se soporta en el futuro)
                if self.backup_callback:
                    await self.backup_callback(schedule.backup_types[0], schedule_id)
            
            # Actualizar estadísticas
            schedule.last_run = datetime.now().isoformat()
            schedule.run_count += 1
            schedule.last_status = "success"
            schedule.next_run = self._calculate_next_run(schedule)
            
            duration = (datetime.now() - start_time).total_seconds()
            self.history.add(
                schedule_id=schedule_id,
                schedule_name=schedule.name,
                backup_types=schedule.backup_types,
                status="success",
                duration_seconds=duration,
                message="Backup completado correctamente"
            )
            
            logger.info(f"✅ Backup programado completado: {schedule.name}")
            
        except Exception as e:
            schedule.last_status = "failed"
            duration = (datetime.now() - start_time).total_seconds()
            self.history.add(
                schedule_id=schedule_id,
                schedule_name=schedule.name,
                backup_types=schedule.backup_types,
                status="failed",
                duration_seconds=duration,
                message=str(e)
            )
            logger.error(f"❌ Error en backup programado {schedule.name}: {e}")
        
        finally:
            self._running_backup = False
            self._save_schedules()
    
    def start(self):
        """Inicia el scheduler"""
        if not self.scheduler.running:
            self.scheduler.start()
            # Registrar todos los schedules activos
            for schedule in self.schedules.values():
                if schedule.status == ScheduleStatus.ACTIVE:
                    self._register_schedule(schedule)
            logger.info("Scheduler iniciado")
    
    def stop(self):
        """Detiene el scheduler"""
        if self.scheduler.running:
            self.scheduler.shutdown()
            logger.info("Scheduler detenido")
    
    def _register_schedule(self, schedule: ScheduleConfig):
        """Registra un schedule en APScheduler"""
        try:
            # Eliminar job existente si hay
            if self.scheduler.get_job(schedule.id):
                self.scheduler.remove_job(schedule.id)
            
            trigger = self._get_trigger(schedule)
            self.scheduler.add_job(
                self._execute_scheduled_backup,
                trigger=trigger,
                id=schedule.id,
                name=schedule.name,
                args=[schedule.id],
                replace_existing=True
            )
            
            # Actualizar next_run
            job = self.scheduler.get_job(schedule.id)
            if job and job.next_run_time:
                schedule.next_run = job.next_run_time.isoformat()
            
            logger.info(f"Schedule registrado: {schedule.name} ({schedule.schedule_type})")
        except Exception as e:
            logger.error(f"Error registrando schedule {schedule.name}: {e}")
    
    def _unregister_schedule(self, schedule_id: str):
        """Elimina un schedule de APScheduler"""
        try:
            if self.scheduler.get_job(schedule_id):
                self.scheduler.remove_job(schedule_id)
                logger.info(f"Schedule eliminado del scheduler: {schedule_id}")
        except Exception as e:
            logger.error(f"Error eliminando schedule {schedule_id}: {e}")
    
    # ============================================
    # API Pública
    # ============================================
    
    def create_schedule(self, config: Dict[str, Any]) -> ScheduleConfig:
        """Crea un nuevo schedule"""
        schedule_id = str(uuid4())[:12]
        config['id'] = schedule_id
        config['created_at'] = datetime.now().isoformat()
        config['updated_at'] = datetime.now().isoformat()
        
        schedule = ScheduleConfig.from_dict(config)
        schedule.next_run = self._calculate_next_run(schedule)
        
        self.schedules[schedule_id] = schedule
        
        if schedule.status == ScheduleStatus.ACTIVE and self.scheduler.running:
            self._register_schedule(schedule)
        
        self._save_schedules()
        return schedule
    
    def update_schedule(self, schedule_id: str, updates: Dict[str, Any]) -> Optional[ScheduleConfig]:
        """Actualiza un schedule existente"""
        if schedule_id not in self.schedules:
            return None
        
        schedule = self.schedules[schedule_id]
        
        # Actualizar campos
        for key, value in updates.items():
            if hasattr(schedule, key) and key not in ['id', 'created_at']:
                if key == 'schedule_type' and isinstance(value, str):
                    value = ScheduleType(value)
                elif key == 'status' and isinstance(value, str):
                    value = ScheduleStatus(value)
                setattr(schedule, key, value)
        
        schedule.updated_at = datetime.now().isoformat()
        schedule.next_run = self._calculate_next_run(schedule)
        
        # Re-registrar si está activo
        if schedule.status == ScheduleStatus.ACTIVE and self.scheduler.running:
            self._register_schedule(schedule)
        else:
            self._unregister_schedule(schedule_id)
        
        self._save_schedules()
        return schedule
    
    def delete_schedule(self, schedule_id: str) -> bool:
        """Elimina un schedule"""
        if schedule_id not in self.schedules:
            return False
        
        self._unregister_schedule(schedule_id)
        del self.schedules[schedule_id]
        self._save_schedules()
        return True
    
    def get_schedule(self, schedule_id: str) -> Optional[ScheduleConfig]:
        """Obtiene un schedule por ID"""
        return self.schedules.get(schedule_id)
    
    def get_all_schedules(self) -> List[ScheduleConfig]:
        """Obtiene todos los schedules"""
        return list(self.schedules.values())
    
    def pause_schedule(self, schedule_id: str) -> Optional[ScheduleConfig]:
        """Pausa un schedule"""
        return self.update_schedule(schedule_id, {'status': ScheduleStatus.PAUSED})
    
    def resume_schedule(self, schedule_id: str) -> Optional[ScheduleConfig]:
        """Reanuda un schedule pausado"""
        return self.update_schedule(schedule_id, {'status': ScheduleStatus.ACTIVE})
    
    def run_now(self, schedule_id: str):
        """Ejecuta un schedule inmediatamente"""
        if schedule_id in self.schedules:
            asyncio.create_task(self._execute_scheduled_backup(schedule_id))
            return True
        return False
    
    def get_history(self, schedule_id: Optional[str] = None, limit: int = 20) -> List[Dict[str, Any]]:
        """Obtiene historial de ejecuciones"""
        if schedule_id:
            return self.history.get_by_schedule(schedule_id, limit)
        return self.history.get_recent(limit)
    
    def get_stats(self) -> Dict[str, Any]:
        """Obtiene estadísticas del scheduler"""
        total = len(self.schedules)
        active = sum(1 for s in self.schedules.values() if s.status == ScheduleStatus.ACTIVE)
        paused = sum(1 for s in self.schedules.values() if s.status == ScheduleStatus.PAUSED)
        
        # Próximas ejecuciones
        upcoming = []
        for schedule in self.schedules.values():
            if schedule.status == ScheduleStatus.ACTIVE and schedule.next_run:
                upcoming.append({
                    'id': schedule.id,
                    'name': schedule.name,
                    'next_run': schedule.next_run,
                    'backup_types': schedule.backup_types
                })
        upcoming.sort(key=lambda x: x['next_run'])
        
        return {
            'total_schedules': total,
            'active': active,
            'paused': paused,
            'disabled': total - active - paused,
            'scheduler_running': self.scheduler.running,
            'upcoming_runs': upcoming[:5],
            'recent_history': self.history.get_recent(5)
        }


# Presets de schedules comunes
SCHEDULE_PRESETS = {
    'daily_night': {
        'name': 'Backup Diario Nocturno',
        'description': 'Backup completo todos los días a las 2:00 AM',
        'schedule_type': ScheduleType.DAILY,
        'time_of_day': '02:00',
        'backup_types': ['global']
    },
    'weekdays_morning': {
        'name': 'Backup Días Laborables',
        'description': 'Backup de MongoDB y PostgreSQL de L-V a las 6:00 AM',
        'schedule_type': ScheduleType.WEEKLY,
        'time_of_day': '06:00',
        'days_of_week': [0, 1, 2, 3, 4],  # Lunes a Viernes
        'backup_types': ['mongodb', 'postgres']
    },
    'weekly_full': {
        'name': 'Backup Semanal Completo',
        'description': 'Backup global todos los domingos a las 3:00 AM',
        'schedule_type': ScheduleType.WEEKLY,
        'time_of_day': '03:00',
        'days_of_week': [6],  # Domingo
        'backup_types': ['global']
    },
    'monthly_archive': {
        'name': 'Backup Mensual',
        'description': 'Backup completo el día 1 de cada mes a las 4:00 AM',
        'schedule_type': ScheduleType.MONTHLY,
        'time_of_day': '04:00',
        'days_of_month': [1],
        'backup_types': ['global']
    },
    'every_6_hours': {
        'name': 'Backup cada 6 horas',
        'description': 'Backup de MongoDB cada 6 horas',
        'schedule_type': ScheduleType.INTERVAL,
        'interval_minutes': 360,
        'backup_types': ['mongodb']
    }
}
