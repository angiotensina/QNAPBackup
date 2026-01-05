import { useState, useEffect, useCallback } from 'react';
import {
  Database,
  HardDrive,
  Server,
  RefreshCw,
  Play,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Loader2,
  Download,
  Upload,
  FolderOpen,
  Activity,
  Box,
  Cpu,
  Calendar,
  Pause,
  Trash2,
  Zap,
  Settings,
} from 'lucide-react';
import { 
  api, 
  SystemStatus, 
  BackupInfo, 
  VolumeInfo, 
  BackupTask, 
  BackupType, 
  DiskUsage,
  Schedule,
  SchedulePreset,
  SchedulerStats,
  ScheduleHistory,
} from './api';

// ============================================
// Components
// ============================================

interface StatusBadgeProps {
  status: boolean;
  trueText: string;
  falseText: string;
}

function StatusBadge({ status, trueText, falseText }: StatusBadgeProps) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${
        status
          ? 'bg-green-500/20 text-green-400'
          : 'bg-red-500/20 text-red-400'
      }`}
    >
      {status ? <CheckCircle size={12} /> : <XCircle size={12} />}
      {status ? trueText : falseText}
    </span>
  );
}

interface CardProps {
  title: string;
  icon: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

function Card({ title, icon, children, className = '' }: CardProps) {
  return (
    <div className={`bg-slate-800 rounded-xl border border-slate-700 overflow-hidden ${className}`}>
      <div className="px-4 py-3 border-b border-slate-700 flex items-center gap-2">
        <span className="text-blue-400">{icon}</span>
        <h3 className="font-semibold text-slate-200">{title}</h3>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

function TaskStatus({ task }: { task: BackupTask }) {
  const statusConfig = {
    pending: { icon: <Clock size={16} />, color: 'text-yellow-400', bg: 'bg-yellow-500/20' },
    running: { icon: <Loader2 size={16} className="animate-spin" />, color: 'text-blue-400', bg: 'bg-blue-500/20' },
    completed: { icon: <CheckCircle size={16} />, color: 'text-green-400', bg: 'bg-green-500/20' },
    failed: { icon: <XCircle size={16} />, color: 'text-red-400', bg: 'bg-red-500/20' },
  };

  const config = statusConfig[task.status];

  return (
    <div className={`flex items-center gap-2 px-3 py-2 rounded-lg ${config.bg}`}>
      <span className={config.color}>{config.icon}</span>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-slate-200 truncate">{task.task_id}</p>
        <p className="text-xs text-slate-400">{task.backup_type}</p>
      </div>
      <span className={`text-xs ${config.color}`}>{task.status}</span>
    </div>
  );
}

// ============================================
// Main App
// ============================================

export default function App() {
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [volumes, setVolumes] = useState<VolumeInfo[]>([]);
  const [tasks, setTasks] = useState<BackupTask[]>([]);
  const [diskUsage, setDiskUsage] = useState<DiskUsage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'dashboard' | 'backups' | 'volumes' | 'tasks' | 'schedules'>('dashboard');
  const [taskOutput, setTaskOutput] = useState<string[]>([]);
  
  // Schedule state
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [schedulerStats, setSchedulerStats] = useState<SchedulerStats | null>(null);
  const [presets, setPresets] = useState<SchedulePreset[]>([]);
  const [scheduleHistory, setScheduleHistory] = useState<ScheduleHistory[]>([]);

  // Fetch data
  const fetchData = useCallback(async () => {
    try {
      setError(null);
      const [statusData, backupsData, volumesData, tasksData, schedulesData, statsData] = await Promise.all([
        api.getStatus().catch(() => null),
        api.getBackups().catch(() => []),
        api.getVolumes().catch(() => []),
        api.getTasks().catch(() => []),
        api.getSchedules().catch(() => []),
        api.getSchedulerStats().catch(() => null),
      ]);

      if (statusData) setStatus(statusData);
      setBackups(backupsData);
      setVolumes(volumesData);
      setTasks(tasksData);
      setSchedules(schedulesData);
      if (statsData) setSchedulerStats(statsData);

      // Get disk usage if QNAP mounted
      if (statusData?.qnap_mounted) {
        const usage = await api.getDiskUsage().catch(() => null);
        if (usage) setDiskUsage(usage);
      }
      
      // Get presets and history for schedules tab
      const [presetsData, historyData] = await Promise.all([
        api.getSchedulePresets().catch(() => ({ presets: [] })),
        api.getScheduleHistory().catch(() => ({ history: [] })),
      ]);
      setPresets(presetsData.presets);
      setScheduleHistory(historyData.history);
      
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error desconocido');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 10000); // Refresh every 10s
    return () => clearInterval(interval);
  }, [fetchData]);

  // Poll active task
  useEffect(() => {
    const activeTask = tasks.find(t => t.status === 'running' || t.status === 'pending');
    if (!activeTask) return;

    const pollTask = async () => {
      try {
        const updated = await api.getTask(activeTask.task_id);
        setTaskOutput(updated.output);
        setTasks(prev => prev.map(t => t.task_id === updated.task_id ? updated : t));
      } catch {
        // Ignore errors
      }
    };

    const interval = setInterval(pollTask, 2000);
    return () => clearInterval(interval);
  }, [tasks]);

  const startBackup = async (type: BackupType) => {
    try {
      const result = await api.startBackup(type);
      setTasks(prev => [{
        task_id: result.task_id,
        backup_type: type,
        status: 'pending',
        started_at: new Date().toISOString(),
        output: [],
      }, ...prev]);
      setActiveTab('tasks');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error iniciando backup');
    }
  };

  const startRestore = async (timestamp: string) => {
    if (!confirm(`¿Restaurar backup ${timestamp}? Esta acción sobrescribirá los datos actuales.`)) {
      return;
    }
    try {
      const result = await api.startRestore(timestamp, ['mongodb', 'milvus', 'postgres', 'additional']);
      setTasks(prev => [{
        task_id: result.task_id,
        backup_type: 'restore',
        status: 'pending',
        started_at: new Date().toISOString(),
        output: [],
      }, ...prev]);
      setActiveTab('tasks');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error iniciando restauración');
    }
  };

  const mountQnap = async () => {
    try {
      await api.mountQnap();
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error montando QNAP');
    }
  };

  // Schedule actions
  const handlePauseSchedule = async (id: string) => {
    try {
      await api.pauseSchedule(id);
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error pausando schedule');
    }
  };

  const handleResumeSchedule = async (id: string) => {
    try {
      await api.resumeSchedule(id);
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error reanudando schedule');
    }
  };

  const handleDeleteSchedule = async (id: string) => {
    if (!confirm('¿Eliminar este schedule de backup?')) return;
    try {
      await api.deleteSchedule(id);
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error eliminando schedule');
    }
  };

  const handleRunNow = async (id: string) => {
    try {
      await api.runScheduleNow(id);
      setActiveTab('tasks');
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error ejecutando schedule');
    }
  };

  const handleCreateFromPreset = async (presetId: string) => {
    try {
      await api.createFromPreset(presetId);
      fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error creando schedule desde preset');
    }
  };

  // Group volumes by category
  const volumesByCategory = volumes.reduce((acc, vol) => {
    if (!acc[vol.category]) acc[vol.category] = [];
    acc[vol.category].push(vol);
    return acc;
  }, {} as Record<string, VolumeInfo[]>);

  const hasRunningTask = tasks.some(t => t.status === 'running' || t.status === 'pending');

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <Loader2 size={48} className="text-blue-500 animate-spin" />
          <p className="text-slate-400">Cargando...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-900">
      {/* Header */}
      <header className="bg-slate-800 border-b border-slate-700 sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-600 rounded-lg">
                <HardDrive size={24} />
              </div>
              <div>
                <h1 className="text-xl font-bold">QNAP Backup Manager</h1>
                <p className="text-sm text-slate-400">Gestión de backups Docker → QNAP NAS</p>
              </div>
            </div>
            <div className="flex items-center gap-4">
              <StatusBadge
                status={status?.docker_running ?? false}
                trueText="Docker"
                falseText="Docker Offline"
              />
              <StatusBadge
                status={status?.qnap_mounted ?? false}
                trueText="QNAP"
                falseText="QNAP Offline"
              />
              <button
                onClick={fetchData}
                className="p-2 hover:bg-slate-700 rounded-lg transition-colors"
                title="Refrescar"
              >
                <RefreshCw size={20} className="text-slate-400" />
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-500/20 border-b border-red-500/30 px-4 py-3">
          <div className="max-w-7xl mx-auto flex items-center gap-2 text-red-400">
            <AlertCircle size={20} />
            <span>{error}</span>
            <button onClick={() => setError(null)} className="ml-auto hover:text-red-300">
              <XCircle size={20} />
            </button>
          </div>
        </div>
      )}

      {/* Navigation */}
      <nav className="bg-slate-800/50 border-b border-slate-700">
        <div className="max-w-7xl mx-auto px-4">
          <div className="flex gap-1">
            {[
              { id: 'dashboard', label: 'Dashboard', icon: <Activity size={18} /> },
              { id: 'backups', label: 'Backups', icon: <FolderOpen size={18} /> },
              { id: 'schedules', label: 'Programación', icon: <Calendar size={18} /> },
              { id: 'volumes', label: 'Volúmenes', icon: <Box size={18} /> },
              { id: 'tasks', label: 'Tareas', icon: <Cpu size={18} /> },
            ].map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as typeof activeTab)}
                className={`flex items-center gap-2 px-4 py-3 text-sm font-medium transition-colors border-b-2 ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-400'
                    : 'border-transparent text-slate-400 hover:text-slate-200'
                }`}
              >
                {tab.icon}
                {tab.label}
                {tab.id === 'schedules' && schedulerStats && (
                  <span className="ml-1 px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-400 rounded">
                    {schedulerStats.active}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 py-6">
        {/* Dashboard */}
        {activeTab === 'dashboard' && (
          <div className="space-y-6">
            {/* Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Contenedores</p>
                    <p className="text-2xl font-bold">{status?.running_containers ?? 0}</p>
                  </div>
                  <Server size={32} className="text-blue-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Volúmenes</p>
                    <p className="text-2xl font-bold">{status?.docker_volumes ?? 0}</p>
                  </div>
                  <HardDrive size={32} className="text-green-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Backups</p>
                    <p className="text-2xl font-bold">{status?.total_backups ?? 0}</p>
                  </div>
                  <FolderOpen size={32} className="text-yellow-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Disco QNAP</p>
                    <p className="text-2xl font-bold">{diskUsage?.percent_used ?? 'N/A'}</p>
                  </div>
                  <Database size={32} className="text-purple-500" />
                </div>
              </div>
            </div>

            {/* QNAP Not Mounted Warning */}
            {!status?.qnap_mounted && (
              <div className="bg-yellow-500/20 border border-yellow-500/30 rounded-xl p-4 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <AlertCircle className="text-yellow-500" size={24} />
                  <div>
                    <p className="font-medium text-yellow-400">QNAP no montado</p>
                    <p className="text-sm text-slate-400">Monta el QNAP para poder realizar backups</p>
                  </div>
                </div>
                <button
                  onClick={mountQnap}
                  className="px-4 py-2 bg-yellow-500 text-black font-medium rounded-lg hover:bg-yellow-400 transition-colors"
                >
                  Montar QNAP
                </button>
              </div>
            )}

            {/* Quick Actions */}
            <Card title="Acciones Rápidas" icon={<Play size={20} />}>
              <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                <button
                  onClick={() => startBackup('global')}
                  disabled={hasRunningTask || !status?.qnap_mounted}
                  className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed border-blue-500/30 bg-blue-500/10 hover:bg-blue-500/20 hover:border-blue-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Download size={24} className="text-blue-400" />
                  <span className="text-sm font-medium">Backup Global</span>
                </button>
                <button
                  onClick={() => startBackup('mongodb')}
                  disabled={hasRunningTask || !status?.qnap_mounted}
                  className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed border-green-500/30 bg-green-500/10 hover:bg-green-500/20 hover:border-green-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Database size={24} className="text-green-400" />
                  <span className="text-sm font-medium">MongoDB</span>
                </button>
                <button
                  onClick={() => startBackup('milvus')}
                  disabled={hasRunningTask || !status?.qnap_mounted}
                  className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed border-purple-500/30 bg-purple-500/10 hover:bg-purple-500/20 hover:border-purple-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Box size={24} className="text-purple-400" />
                  <span className="text-sm font-medium">Milvus</span>
                </button>
                <button
                  onClick={() => startBackup('postgres')}
                  disabled={hasRunningTask || !status?.qnap_mounted}
                  className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed border-yellow-500/30 bg-yellow-500/10 hover:bg-yellow-500/20 hover:border-yellow-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Server size={24} className="text-yellow-400" />
                  <span className="text-sm font-medium">PostgreSQL</span>
                </button>
                <button
                  onClick={() => startBackup('additional')}
                  disabled={hasRunningTask || !status?.qnap_mounted}
                  className="flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 border-dashed border-slate-500/30 bg-slate-500/10 hover:bg-slate-500/20 hover:border-slate-500/50 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <HardDrive size={24} className="text-slate-400" />
                  <span className="text-sm font-medium">Adicionales</span>
                </button>
              </div>
            </Card>

            {/* Recent Backups */}
            <Card title="Últimos Backups" icon={<Clock size={20} />}>
              {backups.length === 0 ? (
                <p className="text-slate-400 text-center py-4">No hay backups disponibles</p>
              ) : (
                <div className="space-y-2">
                  {backups.slice(0, 5).map(backup => (
                    <div
                      key={backup.timestamp}
                      className="flex items-center justify-between p-3 bg-slate-700/50 rounded-lg"
                    >
                      <div className="flex items-center gap-3">
                        <FolderOpen size={20} className="text-blue-400" />
                        <div>
                          <p className="font-medium">{backup.timestamp}</p>
                          <p className="text-sm text-slate-400">{backup.date}</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => startRestore(backup.timestamp)}
                          disabled={hasRunningTask}
                          className="p-2 hover:bg-slate-600 rounded-lg transition-colors disabled:opacity-50"
                          title="Restaurar"
                        >
                          <Upload size={18} className="text-green-400" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Active Tasks */}
            {tasks.filter(t => t.status === 'running' || t.status === 'pending').length > 0 && (
              <Card title="Tareas Activas" icon={<Loader2 size={20} className="animate-spin" />}>
                <div className="space-y-2">
                  {tasks
                    .filter(t => t.status === 'running' || t.status === 'pending')
                    .map(task => (
                      <TaskStatus key={task.task_id} task={task} />
                    ))}
                </div>
                {taskOutput.length > 0 && (
                  <div className="mt-4 p-3 bg-slate-900 rounded-lg max-h-48 overflow-y-auto font-mono text-xs">
                    {taskOutput.slice(-20).map((line, i) => (
                      <div key={i} className="text-slate-400">{line}</div>
                    ))}
                  </div>
                )}
              </Card>
            )}
          </div>
        )}

        {/* Backups Tab */}
        {activeTab === 'backups' && (
          <Card title="Historial de Backups" icon={<FolderOpen size={20} />} className="h-full">
            {backups.length === 0 ? (
              <p className="text-slate-400 text-center py-8">No hay backups disponibles</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-slate-700">
                      <th className="text-left py-3 px-4 text-sm font-medium text-slate-400">Timestamp</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-slate-400">Fecha</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-slate-400">Componentes</th>
                      <th className="text-right py-3 px-4 text-sm font-medium text-slate-400">Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {backups.map(backup => (
                      <tr key={backup.timestamp} className="border-b border-slate-700/50 hover:bg-slate-700/30">
                        <td className="py-3 px-4 font-mono text-sm">{backup.timestamp}</td>
                        <td className="py-3 px-4 text-sm text-slate-400">{backup.date}</td>
                        <td className="py-3 px-4">
                          <div className="flex gap-1">
                            {backup.components && Object.keys(backup.components).map(comp => (
                              <span
                                key={comp}
                                className="px-2 py-0.5 text-xs rounded bg-slate-700 text-slate-300"
                              >
                                {comp}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td className="py-3 px-4 text-right">
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => startRestore(backup.timestamp)}
                              disabled={hasRunningTask}
                              className="p-2 hover:bg-green-500/20 rounded-lg transition-colors disabled:opacity-50"
                              title="Restaurar"
                            >
                              <Upload size={18} className="text-green-400" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        )}

        {/* Volumes Tab */}
        {activeTab === 'volumes' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {Object.entries(volumesByCategory).map(([category, vols]) => (
              <Card
                key={category}
                title={`${category.charAt(0).toUpperCase() + category.slice(1)} (${vols.length})`}
                icon={
                  category === 'mongodb' ? <Database size={20} /> :
                  category === 'milvus' ? <Box size={20} /> :
                  category === 'postgres' ? <Server size={20} /> :
                  <HardDrive size={20} />
                }
              >
                <div className="space-y-1 max-h-64 overflow-y-auto">
                  {vols.map(vol => (
                    <div
                      key={vol.name}
                      className="flex items-center justify-between p-2 hover:bg-slate-700/50 rounded"
                    >
                      <span className="font-mono text-sm truncate">{vol.name}</span>
                      <span className="text-xs text-slate-500">{vol.driver}</span>
                    </div>
                  ))}
                </div>
              </Card>
            ))}
          </div>
        )}

        {/* Tasks Tab */}
        {activeTab === 'tasks' && (
          <Card title="Historial de Tareas" icon={<Cpu size={20} />}>
            {tasks.length === 0 ? (
              <p className="text-slate-400 text-center py-8">No hay tareas registradas</p>
            ) : (
              <div className="space-y-3">
                {tasks.map(task => (
                  <div key={task.task_id} className="bg-slate-700/50 rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        {task.status === 'running' && <Loader2 size={16} className="text-blue-400 animate-spin" />}
                        {task.status === 'completed' && <CheckCircle size={16} className="text-green-400" />}
                        {task.status === 'failed' && <XCircle size={16} className="text-red-400" />}
                        {task.status === 'pending' && <Clock size={16} className="text-yellow-400" />}
                        <span className="font-medium">{task.backup_type}</span>
                        {task.scheduled && (
                          <span className="px-1.5 py-0.5 text-xs bg-purple-500/20 text-purple-400 rounded">
                            Programado
                          </span>
                        )}
                      </div>
                      <span className="text-sm text-slate-400">{task.task_id}</span>
                    </div>
                    <div className="text-sm text-slate-400">
                      <span>Iniciado: {new Date(task.started_at).toLocaleString()}</span>
                      {task.completed_at && (
                        <span className="ml-4">Completado: {new Date(task.completed_at).toLocaleString()}</span>
                      )}
                    </div>
                    {task.error && (
                      <p className="mt-2 text-sm text-red-400">{task.error}</p>
                    )}
                    {task.output.length > 0 && (
                      <div className="mt-3 p-2 bg-slate-900 rounded max-h-32 overflow-y-auto font-mono text-xs">
                        {task.output.slice(-10).map((line, i) => (
                          <div key={i} className="text-slate-400">{line}</div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        )}

        {/* Schedules Tab */}
        {activeTab === 'schedules' && (
          <div className="space-y-6">
            {/* Scheduler Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Schedules Activos</p>
                    <p className="text-2xl font-bold text-green-400">{schedulerStats?.active ?? 0}</p>
                  </div>
                  <CheckCircle size={32} className="text-green-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Pausados</p>
                    <p className="text-2xl font-bold text-yellow-400">{schedulerStats?.paused ?? 0}</p>
                  </div>
                  <Pause size={32} className="text-yellow-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Total</p>
                    <p className="text-2xl font-bold">{schedulerStats?.total_schedules ?? 0}</p>
                  </div>
                  <Calendar size={32} className="text-blue-500" />
                </div>
              </div>
              <div className="bg-slate-800 rounded-xl p-4 border border-slate-700">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-slate-400">Scheduler</p>
                    <p className="text-lg font-bold">
                      {schedulerStats?.scheduler_running ? (
                        <span className="text-green-400">Activo</span>
                      ) : (
                        <span className="text-red-400">Detenido</span>
                      )}
                    </p>
                  </div>
                  <Activity size={32} className={schedulerStats?.scheduler_running ? "text-green-500" : "text-red-500"} />
                </div>
              </div>
            </div>

            {/* Quick Presets */}
            <Card title="Crear desde Preset" icon={<Zap size={20} />}>
              <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-3">
                {presets.map(preset => (
                  <button
                    key={preset.id}
                    onClick={() => handleCreateFromPreset(preset.id)}
                    className="p-3 bg-slate-700/50 hover:bg-slate-700 rounded-lg text-left transition-colors border border-slate-600 hover:border-blue-500/50"
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <Calendar size={16} className="text-blue-400" />
                      <span className="text-sm font-medium truncate">{preset.name}</span>
                    </div>
                    <p className="text-xs text-slate-400 line-clamp-2">{preset.description}</p>
                    <div className="mt-2 flex flex-wrap gap-1">
                      {preset.backup_types.map(type => (
                        <span key={type} className="px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-300 rounded">
                          {type}
                        </span>
                      ))}
                    </div>
                  </button>
                ))}
              </div>
            </Card>

            {/* Schedule List */}
            <Card 
              title="Schedules Configurados" 
              icon={<Settings size={20} />}
              className="min-h-[300px]"
            >
              {schedules.length === 0 ? (
                <div className="text-center py-8">
                  <Calendar size={48} className="mx-auto text-slate-600 mb-3" />
                  <p className="text-slate-400">No hay schedules configurados</p>
                  <p className="text-sm text-slate-500 mt-1">Usa los presets de arriba para crear uno</p>
                </div>
              ) : (
                <div className="space-y-3">
                  {schedules.map(schedule => (
                    <div
                      key={schedule.id}
                      className={`p-4 rounded-lg border ${
                        schedule.status === 'active'
                          ? 'bg-slate-700/50 border-green-500/30'
                          : schedule.status === 'paused'
                          ? 'bg-slate-700/30 border-yellow-500/30'
                          : 'bg-slate-800/50 border-slate-600'
                      }`}
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <h4 className="font-medium">{schedule.name}</h4>
                            <span className={`px-2 py-0.5 text-xs rounded ${
                              schedule.status === 'active' 
                                ? 'bg-green-500/20 text-green-400' 
                                : schedule.status === 'paused'
                                ? 'bg-yellow-500/20 text-yellow-400'
                                : 'bg-slate-500/20 text-slate-400'
                            }`}>
                              {schedule.status}
                            </span>
                            <span className="px-2 py-0.5 text-xs bg-slate-600 text-slate-300 rounded">
                              {schedule.schedule_type}
                            </span>
                          </div>
                          {schedule.description && (
                            <p className="text-sm text-slate-400 mt-1">{schedule.description}</p>
                          )}
                          <div className="flex flex-wrap gap-1 mt-2">
                            {schedule.backup_types.map(type => (
                              <span key={type} className="px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-300 rounded">
                                {type}
                              </span>
                            ))}
                          </div>
                          <div className="flex gap-4 mt-2 text-xs text-slate-400">
                            {schedule.time_of_day && (
                              <span>⏰ {schedule.time_of_day}</span>
                            )}
                            {schedule.cron_expression && (
                              <span>📅 {schedule.cron_expression}</span>
                            )}
                            {schedule.interval_minutes && (
                              <span>🔄 Cada {schedule.interval_minutes} min</span>
                            )}
                            {schedule.days_of_week && (
                              <span>📆 Días: {schedule.days_of_week.map(d => ['L','M','X','J','V','S','D'][d]).join(', ')}</span>
                            )}
                          </div>
                          <div className="flex gap-4 mt-2 text-xs">
                            {schedule.next_run && (
                              <span className="text-green-400">
                                Próximo: {new Date(schedule.next_run).toLocaleString()}
                              </span>
                            )}
                            {schedule.last_run && (
                              <span className="text-slate-400">
                                Último: {new Date(schedule.last_run).toLocaleString()}
                                {schedule.last_status && (
                                  <span className={schedule.last_status === 'success' ? 'text-green-400' : 'text-red-400'}>
                                    {' '}({schedule.last_status})
                                  </span>
                                )}
                              </span>
                            )}
                            <span className="text-slate-500">
                              Ejecuciones: {schedule.run_count}
                            </span>
                          </div>
                        </div>
                        <div className="flex items-center gap-1 ml-4">
                          <button
                            onClick={() => handleRunNow(schedule.id)}
                            disabled={schedule.status !== 'active' || hasRunningTask}
                            className="p-2 hover:bg-slate-600 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                            title="Ejecutar ahora"
                          >
                            <Play size={16} className="text-green-400" />
                          </button>
                          {schedule.status === 'active' ? (
                            <button
                              onClick={() => handlePauseSchedule(schedule.id)}
                              className="p-2 hover:bg-slate-600 rounded-lg transition-colors"
                              title="Pausar"
                            >
                              <Pause size={16} className="text-yellow-400" />
                            </button>
                          ) : (
                            <button
                              onClick={() => handleResumeSchedule(schedule.id)}
                              className="p-2 hover:bg-slate-600 rounded-lg transition-colors"
                              title="Reanudar"
                            >
                              <Play size={16} className="text-blue-400" />
                            </button>
                          )}
                          <button
                            onClick={() => handleDeleteSchedule(schedule.id)}
                            className="p-2 hover:bg-slate-600 rounded-lg transition-colors"
                            title="Eliminar"
                          >
                            <Trash2 size={16} className="text-red-400" />
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Upcoming Runs */}
            {schedulerStats?.upcoming_runs && schedulerStats.upcoming_runs.length > 0 && (
              <Card title="Próximas Ejecuciones" icon={<Clock size={20} />}>
                <div className="space-y-2">
                  {schedulerStats.upcoming_runs.map((run, i) => (
                    <div key={i} className="flex items-center justify-between p-2 bg-slate-700/30 rounded">
                      <div className="flex items-center gap-3">
                        <Clock size={16} className="text-blue-400" />
                        <span className="font-medium">{run.name}</span>
                        <div className="flex gap-1">
                          {run.backup_types.map(type => (
                            <span key={type} className="px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-300 rounded">
                              {type}
                            </span>
                          ))}
                        </div>
                      </div>
                      <span className="text-sm text-green-400">
                        {new Date(run.next_run).toLocaleString()}
                      </span>
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Recent History */}
            {scheduleHistory.length > 0 && (
              <Card title="Historial Reciente" icon={<Activity size={20} />}>
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-slate-700 text-left">
                        <th className="pb-2 text-sm font-medium text-slate-400">Schedule</th>
                        <th className="pb-2 text-sm font-medium text-slate-400">Tipos</th>
                        <th className="pb-2 text-sm font-medium text-slate-400">Estado</th>
                        <th className="pb-2 text-sm font-medium text-slate-400">Duración</th>
                        <th className="pb-2 text-sm font-medium text-slate-400">Fecha</th>
                      </tr>
                    </thead>
                    <tbody>
                      {scheduleHistory.slice(0, 10).map(entry => (
                        <tr key={entry.id} className="border-b border-slate-700/50">
                          <td className="py-2 text-sm">{entry.schedule_name}</td>
                          <td className="py-2">
                            <div className="flex gap-1">
                              {entry.backup_types.map(type => (
                                <span key={type} className="px-1.5 py-0.5 text-xs bg-slate-600 rounded">
                                  {type}
                                </span>
                              ))}
                            </div>
                          </td>
                          <td className="py-2">
                            <span className={`px-2 py-0.5 text-xs rounded ${
                              entry.status === 'success'
                                ? 'bg-green-500/20 text-green-400'
                                : 'bg-red-500/20 text-red-400'
                            }`}>
                              {entry.status}
                            </span>
                          </td>
                          <td className="py-2 text-sm text-slate-400">
                            {Math.round(entry.duration_seconds)}s
                          </td>
                          <td className="py-2 text-sm text-slate-400">
                            {new Date(entry.timestamp).toLocaleString()}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Card>
            )}
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-800 mt-8 py-4">
        <div className="max-w-7xl mx-auto px-4 text-center text-sm text-slate-500">
          QNAP Backup Manager v2.0.0 | Scheduler: {schedulerStats?.scheduler_running ? '🟢' : '🔴'} | {status?.qnap_path}
        </div>
      </footer>
    </div>
  );
}
