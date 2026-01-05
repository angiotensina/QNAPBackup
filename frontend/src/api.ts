// API Types
export interface SystemStatus {
  docker_running: boolean;
  qnap_mounted: boolean;
  qnap_path: string;
  backup_base: string;
  total_backups: number;
  last_backup: string | null;
  docker_volumes: number;
  running_containers: number;
}

export interface VolumeInfo {
  name: string;
  driver: string;
  size?: string;
  category: 'mongodb' | 'milvus' | 'postgres' | 'redis' | 'other';
}

export interface BackupComponent {
  path: string;
  size: string;
  current_size?: string;
}

export interface BackupInfo {
  timestamp: string;
  backup_type: string;
  path: string;
  size?: string;
  date: string;
  components?: Record<string, BackupComponent>;
}

export interface BackupTask {
  task_id: string;
  backup_type: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  started_at: string;
  completed_at?: string;
  output: string[];
  error?: string;
  scheduled?: boolean;
  schedule_id?: string;
}

export interface DiskUsage {
  total: string;
  used: string;
  available: string;
  percent_used: string;
  mount_point: string;
}

export type BackupType = 'mongodb' | 'milvus' | 'postgres' | 'additional' | 'global';
export type ScheduleType = 'cron' | 'interval' | 'daily' | 'weekly' | 'monthly' | 'once';
export type ScheduleStatus = 'active' | 'paused' | 'disabled';

// Schedule Types
export interface Schedule {
  id: string;
  name: string;
  description: string;
  backup_types: BackupType[];
  schedule_type: ScheduleType;
  status: ScheduleStatus;
  cron_expression?: string;
  interval_minutes?: number;
  time_of_day?: string;
  days_of_week?: number[];
  days_of_month?: number[];
  run_date?: string;
  created_at: string;
  updated_at: string;
  last_run?: string;
  next_run?: string;
  run_count: number;
  last_status?: string;
  sequential_execution: boolean;
  retry_on_failure: boolean;
  max_retries: number;
}

export interface ScheduleCreateRequest {
  name: string;
  description?: string;
  backup_types: BackupType[];
  schedule_type: ScheduleType;
  cron_expression?: string;
  interval_minutes?: number;
  time_of_day?: string;
  days_of_week?: number[];
  days_of_month?: number[];
  run_date?: string;
  sequential_execution?: boolean;
  retry_on_failure?: boolean;
  max_retries?: number;
}

export interface ScheduleUpdateRequest {
  name?: string;
  description?: string;
  backup_types?: BackupType[];
  schedule_type?: ScheduleType;
  status?: ScheduleStatus;
  cron_expression?: string;
  interval_minutes?: number;
  time_of_day?: string;
  days_of_week?: number[];
  days_of_month?: number[];
  run_date?: string;
  sequential_execution?: boolean;
  retry_on_failure?: boolean;
  max_retries?: number;
}

export interface SchedulePreset {
  id: string;
  name: string;
  description: string;
  schedule_type: ScheduleType;
  backup_types: BackupType[];
  time_of_day?: string;
  days_of_week?: number[];
  days_of_month?: number[];
  interval_minutes?: number;
}

export interface ScheduleHistory {
  id: string;
  schedule_id: string;
  schedule_name: string;
  backup_types: BackupType[];
  status: 'success' | 'failed';
  duration_seconds: number;
  message: string;
  timestamp: string;
}

export interface SchedulerStats {
  total_schedules: number;
  active: number;
  paused: number;
  disabled: number;
  scheduler_running: boolean;
  upcoming_runs: Array<{
    id: string;
    name: string;
    next_run: string;
    backup_types: BackupType[];
  }>;
  recent_history: ScheduleHistory[];
}

// API Client
const API_BASE = '/api';

async function fetchApi<T>(endpoint: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Error desconocido' }));
    throw new Error(error.detail || `HTTP ${response.status}`);
  }

  return response.json();
}

export const api = {
  // Status
  getStatus: () => fetchApi<SystemStatus>('/status'),
  getHealth: () => fetchApi<{ status: string; timestamp: string }>('/health'),
  
  // Volumes
  getVolumes: () => fetchApi<VolumeInfo[]>('/volumes'),
  
  // Backups
  getBackups: () => fetchApi<BackupInfo[]>('/backups'),
  getBackupDetail: (timestamp: string) => fetchApi<BackupInfo>(`/backups/${timestamp}`),
  startBackup: (type: BackupType) => 
    fetchApi<{ task_id: string; message: string }>(`/backup/${type}`, { method: 'POST' }),
  
  // Restore
  startRestore: (timestamp: string, components: string[]) =>
    fetchApi<{ task_id: string; message: string }>('/restore', {
      method: 'POST',
      body: JSON.stringify({ timestamp, components }),
    }),
  
  // Tasks
  getTasks: () => fetchApi<BackupTask[]>('/tasks'),
  getTask: (taskId: string) => fetchApi<BackupTask>(`/tasks/${taskId}`),
  
  // QNAP
  mountQnap: () => fetchApi<{ status: string; path: string }>('/mount-qnap', { method: 'POST' }),
  getDiskUsage: () => fetchApi<DiskUsage>('/disk-usage'),
  
  // Logs
  getLogs: (timestamp: string) => fetchApi<Record<string, string>>(`/logs/${timestamp}`),
  
  // Schedules
  getSchedules: () => fetchApi<Schedule[]>('/schedules'),
  getSchedule: (id: string) => fetchApi<Schedule>(`/schedules/${id}`),
  getSchedulerStats: () => fetchApi<SchedulerStats>('/schedules/stats'),
  getSchedulePresets: () => fetchApi<{ presets: SchedulePreset[] }>('/schedules/presets'),
  getScheduleHistory: (scheduleId?: string, limit?: number) => {
    const params = new URLSearchParams();
    if (scheduleId) params.append('schedule_id', scheduleId);
    if (limit) params.append('limit', limit.toString());
    const query = params.toString();
    return fetchApi<{ history: ScheduleHistory[] }>(`/schedules/history${query ? `?${query}` : ''}`);
  },
  
  createSchedule: (data: ScheduleCreateRequest) =>
    fetchApi<Schedule>('/schedules', {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  
  createFromPreset: (presetId: string) =>
    fetchApi<Schedule>(`/schedules/from-preset/${presetId}`, { method: 'POST' }),
  
  updateSchedule: (id: string, data: ScheduleUpdateRequest) =>
    fetchApi<Schedule>(`/schedules/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
  
  deleteSchedule: (id: string) =>
    fetchApi<{ status: string; schedule_id: string }>(`/schedules/${id}`, { method: 'DELETE' }),
  
  pauseSchedule: (id: string) =>
    fetchApi<{ status: string; schedule_id: string }>(`/schedules/${id}/pause`, { method: 'POST' }),
  
  resumeSchedule: (id: string) =>
    fetchApi<{ status: string; schedule_id: string }>(`/schedules/${id}/resume`, { method: 'POST' }),
  
  runScheduleNow: (id: string) =>
    fetchApi<{ status: string; schedule_id: string; message: string }>(`/schedules/${id}/run-now`, { method: 'POST' }),
};
