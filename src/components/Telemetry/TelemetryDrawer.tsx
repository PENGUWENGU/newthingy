import React, { useState, useEffect, useRef } from 'react';
import { TelemetryLog } from '../../types';
import { tunnelSimulator } from '../../engine/tunnelSimulator';
import { X, Terminal, Trash2, Activity, ShieldCheck, Cpu } from 'lucide-react';

interface TelemetryDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export const TelemetryDrawer: React.FC<TelemetryDrawerProps> = ({ isOpen, onClose }) => {
  const [logs, setLogs] = useState<TelemetryLog[]>([]);
  const [packetCount, setPacketCount] = useState(0);
  const logContainerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setLogs(tunnelSimulator.getLogs());
    setPacketCount(tunnelSimulator.getPacketCount());

    const unsubscribe = tunnelSimulator.subscribe((newLog) => {
      setLogs((prev) => [newLog, ...prev.slice(0, 150)]);
      setPacketCount(tunnelSimulator.getPacketCount());
    });

    return () => unsubscribe();
  }, []);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[600] flex justify-end bg-black/50 backdrop-blur-sm animate-in fade-in duration-150">
      <div className="w-full max-w-lg bg-slate-950 border-l border-white/10 h-full flex flex-col shadow-2xl animate-in slide-in-from-right duration-200 font-mono">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-white/10 bg-slate-900/80">
          <div className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center border border-emerald-500/30">
              <Terminal className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-xs font-bold text-white tracking-tight">locationd FFI Telemetry</h2>
              <p className="text-[10px] text-slate-400">Live Apple DVT developer tunnel monitor</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-white/10 text-slate-400 hover:text-white transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Telemetry Metrics Ribbon */}
        <div className="grid grid-cols-3 gap-2 p-3 bg-slate-900/40 border-b border-white/5 text-[11px]">
          <div className="bg-slate-900/80 p-2 rounded-xl border border-white/5">
            <span className="text-slate-500 text-[10px] block">Tunnel Status</span>
            <span className="text-emerald-400 font-semibold flex items-center gap-1">
              <ShieldCheck className="w-3 h-3" /> Connected
            </span>
          </div>
          <div className="bg-slate-900/80 p-2 rounded-xl border border-white/5">
            <span className="text-slate-500 text-[10px] block">Injected Frames</span>
            <span className="text-cyan-400 font-semibold flex items-center gap-1">
              <Activity className="w-3 h-3" /> {packetCount} pkts
            </span>
          </div>
          <div className="bg-slate-900/80 p-2 rounded-xl border border-white/5">
            <span className="text-slate-500 text-[10px] block">Protocol</span>
            <span className="text-indigo-300 font-semibold flex items-center gap-1">
              <Cpu className="w-3 h-3" /> DVT 18.0+
            </span>
          </div>
        </div>

        {/* Log stream */}
        <div ref={logContainerRef} className="flex-1 overflow-y-auto p-3 space-y-2 text-[11px] select-text custom-scrollbar">
          {logs.map((log) => {
            let color = 'text-slate-400';
            if (log.level === 'success') color = 'text-emerald-400';
            if (log.level === 'warn') color = 'text-amber-400';
            if (log.level === 'error') color = 'text-rose-400';

            return (
              <div key={log.id} className="p-2 rounded-lg bg-slate-900/50 border border-white/5 flex gap-2">
                <span className="text-slate-500 shrink-0 select-none">[{log.timestamp}]</span>
                <span className={`${color} break-all`}>{log.message}</span>
              </div>
            );
          })}
        </div>

        {/* Footer */}
        <div className="p-3 border-t border-white/10 bg-slate-900/60 flex justify-between items-center text-[10px] text-slate-500">
          <span>Buffer: 150 frames max</span>
          <button
            onClick={() => setLogs([])}
            className="flex items-center gap-1 text-slate-400 hover:text-white transition-colors"
          >
            <Trash2 className="w-3 h-3" />
            <span>Clear Stream</span>
          </button>
        </div>
      </div>
    </div>
  );
};
