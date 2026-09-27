import React, { useState } from 'react';
import { Coordinate, SpoofStatus } from '../../types';
import {
  Play,
  Square,
  Pause,
  MapPin,
  Search,
  Bookmark,
  Route,
  Terminal,
  Settings,
  Sparkles,
  Radio,
  Copy,
  Check,
} from 'lucide-react';

interface TopStatusBarProps {
  currentLocation: Coordinate;
  targetPin: Coordinate | null;
  spoofStatus: SpoofStatus;
  onStartSpoofing: () => void;
  onPauseSpoofing: () => void;
  onStopSpoofing: () => void;
  onTeleportToTarget: () => void;
  onSearchPlace: (query: string) => Promise<void>;
  onOpenRoutes: () => void;
  onOpenSavedPlaces: () => void;
  onOpenTelemetry: () => void;
  onOpenSettings: () => void;
  onOpenSetup: () => void;
}

export const TopStatusBar: React.FC<TopStatusBarProps> = ({
  currentLocation,
  targetPin,
  spoofStatus,
  onStartSpoofing,
  onPauseSpoofing,
  onStopSpoofing,
  onTeleportToTarget,
  onSearchPlace,
  onOpenRoutes,
  onOpenSavedPlaces,
  onOpenTelemetry,
  onOpenSettings,
  onOpenSetup,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [copied, setCopied] = useState(false);

  const handleSearchSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!searchQuery.trim()) return;
    setIsSearching(true);
    try {
      await onSearchPlace(searchQuery);
    } finally {
      setIsSearching(false);
    }
  };

  const handleCopyCoords = () => {
    const text = `${currentLocation.latitude.toFixed(6)}, ${currentLocation.longitude.toFixed(6)}`;
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <header className="absolute top-3 left-3 right-3 z-[500] flex flex-wrap items-center justify-between gap-2 pointer-events-none">
      {/* Left Pill: Brand & Status & Live Telemetry Coordinates */}
      <div className="flex items-center gap-2 bg-slate-900/90 backdrop-blur-xl border border-white/10 p-1.5 pl-3 rounded-2xl shadow-2xl pointer-events-auto max-w-full overflow-x-auto">
        {/* Brand Icon & Status */}
        <div className="flex items-center gap-2 pr-2 border-r border-white/10">
          <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-cyan-500 to-blue-600 flex items-center justify-center shadow-lg shadow-cyan-500/25">
            <Radio className={`w-4 h-4 text-white ${spoofStatus === 'spoofing' ? 'animate-pulse' : ''}`} />
          </div>
          <div className="flex flex-col">
            <span className="text-xs font-bold tracking-tight text-white flex items-center gap-1.5">
              Locus
              <span
                className={`text-[9px] px-1.5 py-0.2 rounded-full uppercase tracking-wider font-mono font-bold ${
                  spoofStatus === 'spoofing'
                    ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                    : spoofStatus === 'paused'
                    ? 'bg-amber-500/20 text-amber-400 border border-amber-500/30'
                    : 'bg-slate-800 text-slate-400 border border-white/5'
                }`}
              >
                {spoofStatus}
              </span>
            </span>
            <span className="text-[10px] text-slate-400 font-mono">DVT Location Tunnel</span>
          </div>
        </div>

        {/* Current Live Coordinates & Click to Copy */}
        <button
          onClick={handleCopyCoords}
          title="Click to copy coordinates"
          className="flex items-center gap-2 px-2.5 py-1 rounded-xl bg-slate-950/60 hover:bg-slate-950 border border-white/5 text-slate-300 transition-colors group"
        >
          <div className="flex flex-col text-left">
            <span className="text-[11px] font-mono text-cyan-400 font-semibold tracking-tight">
              {currentLocation.latitude.toFixed(6)}, {currentLocation.longitude.toFixed(6)}
            </span>
            <div className="flex items-center gap-2 text-[9px] text-slate-400 font-mono">
              <span>Spd: {currentLocation.speedKmh ? currentLocation.speedKmh.toFixed(1) : '0.0'} km/h</span>
              <span>•</span>
              <span>Alt: {currentLocation.altitude || 10}m</span>
              <span>•</span>
              <span>Hdg: {Math.round(currentLocation.heading || 0)}°</span>
            </div>
          </div>
          {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5 text-slate-500 group-hover:text-slate-300" />}
        </button>

        {/* Teleport to Selected Target Pin Button */}
        {targetPin && (
          <button
            onClick={onTeleportToTarget}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-gradient-to-r from-rose-500 to-rose-600 hover:from-rose-600 hover:to-rose-700 text-white text-xs font-semibold shadow-lg shadow-rose-500/30 active:scale-95 transition-all animate-bounce"
          >
            <MapPin className="w-3.5 h-3.5" />
            <span>Teleport Here</span>
          </button>
        )}

        {/* Spoof Control Action (Play / Pause / Stop) */}
        <div className="flex items-center gap-1 pl-1">
          {spoofStatus === 'disconnected' || spoofStatus === 'idle' ? (
            <button
              onClick={onStartSpoofing}
              title="Start Developer Spoofing"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-600 text-white text-xs font-bold shadow-md shadow-emerald-500/25 active:scale-95 transition-all"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              <span>Start</span>
            </button>
          ) : (
            <>
              {spoofStatus === 'spoofing' ? (
                <button
                  onClick={onPauseSpoofing}
                  title="Pause Spoofing"
                  className="p-1.5 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 border border-amber-500/30 active:scale-95 transition-all"
                >
                  <Pause className="w-4 h-4" />
                </button>
              ) : (
                <button
                  onClick={onStartSpoofing}
                  title="Resume Spoofing"
                  className="p-1.5 rounded-xl bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-400 border border-emerald-500/30 active:scale-95 transition-all"
                >
                  <Play className="w-4 h-4 fill-current" />
                </button>
              )}
              <button
                onClick={onStopSpoofing}
                title="Stop & Clear Location"
                className="p-1.5 rounded-xl bg-rose-500/20 hover:bg-rose-500/30 text-rose-400 border border-rose-500/30 active:scale-95 transition-all"
              >
                <Square className="w-4 h-4 fill-current" />
              </button>
            </>
          )}
        </div>
      </div>

      {/* Right Controls: Search & Feature Action Bar */}
      <div className="flex items-center gap-2 bg-slate-900/90 backdrop-blur-xl border border-white/10 p-1.5 rounded-2xl shadow-2xl pointer-events-auto">
        {/* Search Place Form */}
        <form onSubmit={handleSearchSubmit} className="relative flex items-center">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search place, city or lat, lng..."
            className="w-48 sm:w-64 bg-slate-950/80 border border-white/10 focus:border-cyan-400/60 rounded-xl pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none transition-all"
          />
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 pointer-events-none" />
          {isSearching && (
            <div className="absolute right-2.5 w-3 h-3 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin" />
          )}
        </form>

        {/* Routes Button */}
        <button
          onClick={onOpenRoutes}
          title="Routes & GPX Planner"
          className="p-2 rounded-xl bg-slate-800/70 hover:bg-slate-800 text-slate-300 hover:text-white border border-white/5 active:scale-95 transition-all"
        >
          <Route className="w-4 h-4 text-cyan-400" />
        </button>

        {/* Saved Places / Favorites */}
        <button
          onClick={onOpenSavedPlaces}
          title="Saved Places & Favorites"
          className="p-2 rounded-xl bg-slate-800/70 hover:bg-slate-800 text-slate-300 hover:text-white border border-white/5 active:scale-95 transition-all"
        >
          <Bookmark className="w-4 h-4 text-amber-400" />
        </button>

        {/* Telemetry Stream */}
        <button
          onClick={onOpenTelemetry}
          title="locationd Telemetry & Logs"
          className="p-2 rounded-xl bg-slate-800/70 hover:bg-slate-800 text-slate-300 hover:text-white border border-white/5 active:scale-95 transition-all"
        >
          <Terminal className="w-4 h-4 text-emerald-400" />
        </button>

        {/* Setup Walkthrough */}
        <button
          onClick={onOpenSetup}
          title="Setup & Pairing Guide"
          className="p-2 rounded-xl bg-slate-800/70 hover:bg-slate-800 text-slate-300 hover:text-white border border-white/5 active:scale-95 transition-all"
        >
          <Sparkles className="w-4 h-4 text-purple-400" />
        </button>

        {/* Settings */}
        <button
          onClick={onOpenSettings}
          title="Locus Settings & Tunnel Config"
          className="p-2 rounded-xl bg-slate-800/70 hover:bg-slate-800 text-slate-300 hover:text-white border border-white/5 active:scale-95 transition-all"
        >
          <Settings className="w-4 h-4 text-slate-300" />
        </button>
      </div>
    </header>
  );
};
