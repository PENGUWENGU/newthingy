import React, { useState, useRef } from 'react';
import { SimulatedRoute, Waypoint, TravelMode, Coordinate } from '../../types';
import { interpolateWaypoints, generateGPX, parseGPX, TRAVEL_MODES } from '../../engine/locationEngine';
import {
  X,
  Plus,
  Trash2,
  Play,
  Pause,
  RotateCcw,
  Upload,
  Download,
  MapPin,
  Clock,
  Gauge,
  Repeat,
  Sparkles,
  MoveUp,
  MoveDown,
  Navigation,
} from 'lucide-react';

interface RoutePlannerModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentLocation: Coordinate;
  activeRoute: SimulatedRoute | null;
  onLoadRoute: (route: SimulatedRoute) => void;
  onClearRoute: () => void;
  isPlayingSimulation: boolean;
  onTogglePlaySimulation: () => void;
  routeProgressPct: number;
  onSeekRoute: (pct: number) => void;
  simulationMultiplier: number;
  onSimulationMultiplierChange: (mult: number) => void;
}

const PRESET_ROUTES: { name: string; mode: TravelMode; waypoints: Omit<Waypoint, 'id'>[] }[] = [
  {
    name: 'San Francisco: Embarcadero to Golden Gate View',
    mode: 'cycle',
    waypoints: [
      { name: 'Ferry Building', latitude: 37.7955, longitude: -122.3937 },
      { name: 'Pier 39', latitude: 37.8087, longitude: -122.4098 },
      { name: 'Fort Mason', latitude: 37.8058, longitude: -122.4285 },
      { name: 'Crissy Field Beach', latitude: 37.8048, longitude: -122.4595 },
      { name: 'Fort Point View', latitude: 37.8105, longitude: -122.4771 },
    ],
  },
  {
    name: 'Tokyo: Shibuya to Harajuku & Meiji Shrine',
    mode: 'walk',
    waypoints: [
      { name: 'Shibuya Crossing', latitude: 35.6595, longitude: 139.7004 },
      { name: 'Miyashita Park', latitude: 35.6625, longitude: 139.7022 },
      { name: 'Cat Street Harajuku', latitude: 35.6668, longitude: 139.7058 },
      { name: 'Takeshita Street', latitude: 35.6715, longitude: 139.7032 },
      { name: 'Meiji Jingu Torii Gate', latitude: 35.6764, longitude: 139.6993 },
    ],
  },
  {
    name: 'New York: Central Park Scenic Loop',
    mode: 'run',
    waypoints: [
      { name: 'Columbus Circle', latitude: 40.7681, longitude: -73.9819 },
      { name: 'Sheep Meadow', latitude: 40.7718, longitude: -73.9749 },
      { name: 'Bethesda Terrace', latitude: 40.7744, longitude: -73.9708 },
      { name: 'The Ramble', latitude: 40.7778, longitude: -73.9692 },
      { name: 'Reservoir South Gate', latitude: 40.7854, longitude: -73.9648 },
    ],
  },
  {
    name: 'Paris: Eiffel Tower along Seine to Louvre',
    mode: 'walk',
    waypoints: [
      { name: 'Champ de Mars', latitude: 48.8556, longitude: 2.2986 },
      { name: 'Eiffel Tower', latitude: 48.8584, longitude: 2.2945 },
      { name: 'Pont Alexandre III', latitude: 48.8637, longitude: 2.3136 },
      { name: 'Musée d\'Orsay', latitude: 48.8599, longitude: 2.3266 },
      { name: 'Louvre Pyramid', latitude: 48.8606, longitude: 2.3376 },
    ],
  },
];

export const RoutePlannerModal: React.FC<RoutePlannerModalProps> = ({
  isOpen,
  onClose,
  currentLocation,
  activeRoute,
  onLoadRoute,
  onClearRoute,
  isPlayingSimulation,
  onTogglePlaySimulation,
  routeProgressPct,
  onSeekRoute,
  simulationMultiplier,
  onSimulationMultiplierChange,
}) => {
  const [routeName, setRouteName] = useState('My Custom Route');
  const [waypoints, setWaypoints] = useState<Waypoint[]>([
    {
      id: 'wpt-1',
      name: 'Start Location',
      latitude: currentLocation.latitude,
      longitude: currentLocation.longitude,
    },
    {
      id: 'wpt-2',
      name: 'Destination',
      latitude: currentLocation.latitude + 0.005,
      longitude: currentLocation.longitude + 0.005,
    },
  ]);
  const [travelMode, setTravelMode] = useState<TravelMode>('walk');
  const [isLoop, setIsLoop] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!isOpen) return null;

  const handleAddWaypoint = () => {
    const last = waypoints[waypoints.length - 1] || { latitude: currentLocation.latitude, longitude: currentLocation.longitude };
    const newWpt: Waypoint = {
      id: `wpt-${Date.now()}`,
      name: `Waypoint ${waypoints.length + 1}`,
      latitude: last.latitude + (Math.random() * 0.003 - 0.0015),
      longitude: last.longitude + (Math.random() * 0.003 - 0.0015),
    };
    setWaypoints([...waypoints, newWpt]);
  };

  const handleUpdateWaypoint = (id: string, field: keyof Waypoint, value: any) => {
    setWaypoints(
      waypoints.map((w) => {
        if (w.id === id) {
          return { ...w, [field]: value };
        }
        return w;
      })
    );
  };

  const handleRemoveWaypoint = (id: string) => {
    if (waypoints.length <= 2) return;
    setWaypoints(waypoints.filter((w) => w.id !== id));
  };

  const handleBuildAndLoadRoute = () => {
    if (waypoints.length < 2) return;

    let effectiveWaypoints = [...waypoints];
    if (isLoop && waypoints.length > 2) {
      effectiveWaypoints.push({
        id: `wpt-loop-${Date.now()}`,
        name: `${waypoints[0].name} (Return)`,
        latitude: waypoints[0].latitude,
        longitude: waypoints[0].longitude,
      });
    }

    const { path, totalDistance } = interpolateWaypoints(effectiveWaypoints, 6);
    const speedKmh = TRAVEL_MODES[travelMode].defaultSpeedKmh;
    const speedMs = (speedKmh * 1000) / 3600;
    const estimatedSecs = totalDistance / speedMs;

    const route: SimulatedRoute = {
      id: `route-${Date.now()}`,
      name: routeName,
      waypoints: effectiveWaypoints,
      pathCoordinates: path,
      totalDistanceMeters: totalDistance,
      estimatedDurationSeconds: estimatedSecs,
      mode: travelMode,
      loop: isLoop,
      reverseOnEnd: false,
    };

    onLoadRoute(route);
  };

  const handleExportGPX = () => {
    if (!activeRoute) {
      handleBuildAndLoadRoute();
    }
    const routeToExport = activeRoute || {
      id: 'temp',
      name: routeName,
      waypoints,
      pathCoordinates: interpolateWaypoints(waypoints).path,
      totalDistanceMeters: 1000,
      estimatedDurationSeconds: 600,
      mode: travelMode,
      loop: isLoop,
      reverseOnEnd: false,
    };

    const gpxText = generateGPX(routeToExport);
    const blob = new Blob([gpxText], { type: 'application/gpx+xml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${routeToExport.name.toLowerCase().replace(/\s+/g, '_')}.gpx`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImportGPXFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      const content = event.target?.result as string;
      if (!content) return;

      try {
        const parsed = parseGPX(content);
        setRouteName(parsed.name);
        if (parsed.waypoints.length >= 2) {
          setWaypoints(parsed.waypoints);
        } else if (parsed.coordinates.length >= 2) {
          const generatedWpts: Waypoint[] = parsed.coordinates.slice(0, 10).map((c, i) => ({
            id: `wpt-imp-${i}`,
            name: `Trackpoint ${i + 1}`,
            latitude: c[0],
            longitude: c[1],
          }));
          setWaypoints(generatedWpts);
        }

        const { path, totalDistance } = interpolateWaypoints(
          parsed.waypoints.length >= 2 ? parsed.waypoints : [
            { id: '1', latitude: parsed.coordinates[0][0], longitude: parsed.coordinates[0][1] },
            { id: '2', latitude: parsed.coordinates[parsed.coordinates.length - 1][0], longitude: parsed.coordinates[parsed.coordinates.length - 1][1] },
          ]
        );

        onLoadRoute({
          id: `route-imported-${Date.now()}`,
          name: parsed.name,
          waypoints: parsed.waypoints.length >= 2 ? parsed.waypoints : [],
          pathCoordinates: parsed.coordinates.length > 0 ? parsed.coordinates : path,
          totalDistanceMeters: totalDistance,
          estimatedDurationSeconds: 1200,
          mode: travelMode,
          loop: false,
          reverseOnEnd: false,
        });
      } catch (err) {
        console.error('Failed to parse GPX', err);
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleLoadPreset = (preset: typeof PRESET_ROUTES[0]) => {
    setRouteName(preset.name);
    setTravelMode(preset.mode);
    const loadedWpts: Waypoint[] = preset.waypoints.map((w, idx) => ({
      ...w,
      id: `preset-wpt-${idx}-${Date.now()}`,
    }));
    setWaypoints(loadedWpts);

    const { path, totalDistance } = interpolateWaypoints(loadedWpts, 6);
    const speedKmh = TRAVEL_MODES[preset.mode].defaultSpeedKmh;
    const speedMs = (speedKmh * 1000) / 3600;

    onLoadRoute({
      id: `route-preset-${Date.now()}`,
      name: preset.name,
      waypoints: loadedWpts,
      pathCoordinates: path,
      totalDistanceMeters: totalDistance,
      estimatedDurationSeconds: totalDistance / speedMs,
      mode: preset.mode,
      loop: false,
      reverseOnEnd: false,
    });
  };

  return (
    <div className="fixed inset-0 z-[600] flex items-center justify-center p-4 bg-black/60 backdrop-blur-md">
      <div className="bg-slate-900 border border-white/10 rounded-3xl w-full max-w-2xl max-h-[90vh] flex flex-col shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-white/10 bg-slate-950/50">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-cyan-500/20 text-cyan-400 flex items-center justify-center border border-cyan-500/30">
              <Navigation className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white tracking-tight">Route & GPX Planner</h2>
              <p className="text-xs text-slate-400">MapKit simulated pathing with automatic waypoint interpolation</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-white/10 text-slate-400 hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 overflow-y-auto space-y-5 flex-1 custom-scrollbar">
          {/* Active Simulation Controller (If route is loaded) */}
          {activeRoute && (
            <div className="bg-gradient-to-br from-cyan-950/40 to-slate-950/80 border border-cyan-500/30 rounded-2xl p-4 shadow-lg">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <span className="text-xs font-mono text-cyan-400 uppercase tracking-wider font-semibold">Active Route</span>
                  <h3 className="text-sm font-bold text-white">{activeRoute.name}</h3>
                </div>
                <div className="flex items-center gap-3 text-xs text-slate-300 font-mono">
                  <span>{(activeRoute.totalDistanceMeters / 1000).toFixed(2)} km</span>
                  <span>•</span>
                  <span>~{Math.round(activeRoute.estimatedDurationSeconds / 60)} min</span>
                </div>
              </div>

              {/* Progress Slider */}
              <div className="space-y-1.5 mb-4">
                <div className="flex justify-between text-[11px] text-slate-400 font-mono">
                  <span>Progress: {Math.round(routeProgressPct)}%</span>
                  <span>{TRAVEL_MODES[activeRoute.mode].name} Mode</span>
                </div>
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={routeProgressPct}
                  onChange={(e) => onSeekRoute(parseFloat(e.target.value))}
                  className="w-full accent-cyan-400 h-2 bg-slate-800 rounded-lg cursor-pointer"
                />
              </div>

              {/* Playback Actions Bar */}
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <button
                    onClick={onTogglePlaySimulation}
                    className={`flex items-center gap-1.5 px-4 py-2 rounded-xl font-semibold text-xs transition-all shadow-md ${
                      isPlayingSimulation
                        ? 'bg-amber-500 hover:bg-amber-600 text-slate-950'
                        : 'bg-cyan-500 hover:bg-cyan-600 text-white'
                    }`}
                  >
                    {isPlayingSimulation ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5 fill-current" />}
                    <span>{isPlayingSimulation ? 'Pause Simulation' : 'Drive Route'}</span>
                  </button>

                  <button
                    onClick={() => onSeekRoute(0)}
                    title="Reset to Start"
                    className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 transition-colors"
                  >
                    <RotateCcw className="w-4 h-4" />
                  </button>

                  <button
                    onClick={onClearRoute}
                    className="px-3 py-2 rounded-xl bg-slate-800/80 hover:bg-rose-950/40 text-rose-400 text-xs border border-rose-500/20 transition-colors"
                  >
                    Clear Route
                  </button>
                </div>

                {/* Speed Multiplier */}
                <div className="flex items-center gap-1 bg-slate-950 p-1 rounded-xl border border-white/5 text-xs font-mono">
                  <Gauge className="w-3.5 h-3.5 text-slate-400 ml-1 mr-0.5" />
                  {[1, 2, 5, 10].map((m) => (
                    <button
                      key={m}
                      onClick={() => onSimulationMultiplierChange(m)}
                      className={`px-2 py-0.5 rounded-lg transition-all ${
                        simulationMultiplier === m ? 'bg-cyan-500 text-white font-bold' : 'text-slate-400 hover:text-white'
                      }`}
                    >
                      {m}x
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Preset Routes Selector */}
          <div>
            <div className="flex items-center gap-2 mb-2 text-xs font-semibold text-slate-300">
              <Sparkles className="w-3.5 h-3.5 text-purple-400" />
              <span>Explore Famous Simulated Paths</span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {PRESET_ROUTES.map((p) => (
                <button
                  key={p.name}
                  onClick={() => handleLoadPreset(p)}
                  className="p-3 text-left rounded-2xl bg-slate-950/60 hover:bg-slate-800/60 border border-white/5 hover:border-cyan-500/30 transition-all group"
                >
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs font-bold text-slate-200 group-hover:text-cyan-400">{p.name.split(':')[0]}</span>
                    <span className="text-[10px] px-2 py-0.5 rounded-md bg-slate-800 text-slate-400 font-mono capitalize">
                      {p.mode}
                    </span>
                  </div>
                  <p className="text-[11px] text-slate-500 line-clamp-1">{p.name.split(':')[1]}</p>
                </button>
              ))}
            </div>
          </div>

          {/* Route Configuration Form */}
          <div className="space-y-4 pt-2 border-t border-white/5">
            <div className="flex flex-col sm:flex-row gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-slate-400 mb-1">Route Name</label>
                <input
                  type="text"
                  value={routeName}
                  onChange={(e) => setRouteName(e.target.value)}
                  className="w-full bg-slate-950 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-400"
                />
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-400 mb-1">Travel Mode</label>
                <select
                  value={travelMode}
                  onChange={(e) => setTravelMode(e.target.value as TravelMode)}
                  className="bg-slate-950 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-cyan-400 capitalize"
                >
                  {(['walk', 'run', 'cycle', 'drive'] as TravelMode[]).map((m) => (
                    <option key={m} value={m}>
                      {TRAVEL_MODES[m].name} (~{TRAVEL_MODES[m].defaultSpeedKmh} km/h)
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Waypoints List */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-xs font-semibold text-slate-300 flex items-center gap-1.5">
                  <MapPin className="w-3.5 h-3.5 text-cyan-400" />
                  <span>Waypoints ({waypoints.length})</span>
                </label>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setIsLoop(!isLoop)}
                    className={`flex items-center gap-1 text-[11px] px-2 py-1 rounded-lg border transition-all ${
                      isLoop ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40' : 'text-slate-400 border-white/5'
                    }`}
                  >
                    <Repeat className="w-3 h-3" />
                    <span>Loop Return</span>
                  </button>
                  <button
                    onClick={handleAddWaypoint}
                    className="flex items-center gap-1 text-xs text-cyan-400 hover:text-cyan-300 bg-cyan-500/10 hover:bg-cyan-500/20 px-2.5 py-1 rounded-lg transition-all"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add Point</span>
                  </button>
                </div>
              </div>

              <div className="space-y-2 max-h-48 overflow-y-auto pr-1">
                {waypoints.map((wpt, idx) => (
                  <div
                    key={wpt.id}
                    className="flex items-center gap-2 bg-slate-950/70 p-2 rounded-xl border border-white/5"
                  >
                    <div className="w-6 h-6 rounded-full bg-slate-800 text-slate-300 text-[10px] font-bold flex items-center justify-center font-mono">
                      {idx === 0 ? 'A' : idx === waypoints.length - 1 ? 'B' : idx + 1}
                    </div>

                    <input
                      type="text"
                      value={wpt.name || ''}
                      onChange={(e) => handleUpdateWaypoint(wpt.id, 'name', e.target.value)}
                      placeholder={`Point ${idx + 1}`}
                      className="flex-1 bg-slate-900 border border-white/5 rounded-lg px-2.5 py-1 text-xs text-white"
                    />

                    <input
                      type="number"
                      step="0.0001"
                      value={wpt.latitude}
                      onChange={(e) => handleUpdateWaypoint(wpt.id, 'latitude', parseFloat(e.target.value))}
                      className="w-24 bg-slate-900 border border-white/5 rounded-lg px-2 py-1 text-xs text-cyan-400 font-mono"
                    />

                    <input
                      type="number"
                      step="0.0001"
                      value={wpt.longitude}
                      onChange={(e) => handleUpdateWaypoint(wpt.id, 'longitude', parseFloat(e.target.value))}
                      className="w-24 bg-slate-900 border border-white/5 rounded-lg px-2 py-1 text-xs text-cyan-400 font-mono"
                    />

                    {waypoints.length > 2 && (
                      <button
                        onClick={() => handleRemoveWaypoint(wpt.id)}
                        className="p-1 text-slate-500 hover:text-rose-400 transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-white/10 bg-slate-950/50 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <input
              type="file"
              ref={fileInputRef}
              accept=".gpx"
              onChange={handleImportGPXFile}
              className="hidden"
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium border border-white/5 transition-all"
            >
              <Upload className="w-3.5 h-3.5" />
              <span>Import GPX</span>
            </button>
            <button
              onClick={handleExportGPX}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium border border-white/5 transition-all"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export GPX</span>
            </button>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-slate-400 hover:text-white text-xs font-medium transition-colors"
            >
              Close
            </button>
            <button
              onClick={() => {
                handleBuildAndLoadRoute();
                onClose();
              }}
              className="flex items-center gap-1.5 px-5 py-2 rounded-xl bg-cyan-500 hover:bg-cyan-600 text-white text-xs font-bold shadow-lg shadow-cyan-500/30 transition-all"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              <span>Load on Map</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
