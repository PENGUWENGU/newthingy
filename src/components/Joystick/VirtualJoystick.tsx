import React, { useState, useRef, useEffect, useCallback } from 'react';
import { TravelMode } from '../../types';
import { TRAVEL_MODES, computeDestination, applySpeedJitter } from '../../engine/locationEngine';
import { Footprints, Zap, Bike, Car, Sliders, Lock, Unlock, ArrowUp, Compass } from 'lucide-react';

interface VirtualJoystickProps {
  currentMode: TravelMode;
  onModeChange: (mode: TravelMode) => void;
  customSpeedKmh: number;
  onCustomSpeedChange: (speed: number) => void;
  onStepMove: (bearing: number, distanceMeters: number, currentSpeed: number) => void;
  isSpoofing: boolean;
  onStartSpoofing: () => void;
}

export const VirtualJoystick: React.FC<VirtualJoystickProps> = ({
  currentMode,
  onModeChange,
  customSpeedKmh,
  onCustomSpeedChange,
  onStepMove,
  isSpoofing,
  onStartSpoofing,
}) => {
  const [isDragging, setIsDragging] = useState(false);
  const [knobPos, setKnobPos] = useState({ x: 0, y: 0 });
  const [isLocked, setIsLocked] = useState(false);
  const [currentBearing, setCurrentBearing] = useState<number | null>(null);
  const [currentSpeed, setCurrentSpeed] = useState<number>(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const activeIntervalRef = useRef<number | null>(null);

  const radius = 60; // max joystick drag radius

  // Mode configs
  const modeConfig = TRAVEL_MODES[currentMode];
  const effectiveBaseSpeed = currentMode === 'custom' ? customSpeedKmh : modeConfig.defaultSpeedKmh;

  // Handle pointer down / move / up
  const handlePointerDown = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    setIsDragging(true);
    updateKnob(e.clientX, e.clientY);
  };

  const updateKnob = useCallback(
    (clientX: number, clientY: number) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;

      const dx = clientX - centerX;
      const dy = clientY - centerY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      const clampedDist = Math.min(dist, radius);
      const angleRad = Math.atan2(dy, dx);
      // Bearing: 0 = North (-Y), 90 = East (+X), 180 = South (+Y), 270 = West (-X)
      let bearing = (Math.atan2(dx, -dy) * 180) / Math.PI;
      if (bearing < 0) bearing += 360;

      const x = Math.cos(angleRad) * clampedDist;
      const y = Math.sin(angleRad) * clampedDist;

      setKnobPos({ x, y });
      setCurrentBearing(bearing);

      const intensity = clampedDist / radius;
      const jitteredSpeed = applySpeedJitter(effectiveBaseSpeed * intensity, modeConfig.speedJitterPct);
      setCurrentSpeed(jitteredSpeed);
    },
    [radius, effectiveBaseSpeed, modeConfig.speedJitterPct]
  );

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!isDragging && !isLocked) return;
    updateKnob(e.clientX, e.clientY);
  };

  const handlePointerUp = () => {
    if (!isLocked) {
      setIsDragging(false);
      setKnobPos({ x: 0, y: 0 });
      setCurrentBearing(null);
      setCurrentSpeed(0);
    }
  };

  // Keyboard navigation support (Arrow Keys or WASD)
  useEffect(() => {
    const activeKeys = new Set<string>();

    const handleKeyDown = (e: KeyboardEvent) => {
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'w', 'a', 's', 'd', 'W', 'A', 'S', 'D'].includes(e.key)) {
        activeKeys.add(e.key.toLowerCase());
        computeKeyJoystick();
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      activeKeys.delete(e.key.toLowerCase());
      if (activeKeys.size === 0 && !isLocked) {
        setKnobPos({ x: 0, y: 0 });
        setCurrentBearing(null);
        setCurrentSpeed(0);
      } else {
        computeKeyJoystick();
      }
    };

    const computeKeyJoystick = () => {
      let dx = 0;
      let dy = 0;
      if (activeKeys.has('arrowup') || activeKeys.has('w')) dy -= 1;
      if (activeKeys.has('arrowdown') || activeKeys.has('s')) dy += 1;
      if (activeKeys.has('arrowleft') || activeKeys.has('a')) dx -= 1;
      if (activeKeys.has('arrowright') || activeKeys.has('d')) dx += 1;

      if (dx === 0 && dy === 0) return;

      const len = Math.sqrt(dx * dx + dy * dy);
      const nx = (dx / len) * radius;
      const ny = (dy / len) * radius;

      let bearing = (Math.atan2(nx, -ny) * 180) / Math.PI;
      if (bearing < 0) bearing += 360;

      setKnobPos({ x: nx, y: ny });
      setCurrentBearing(bearing);
      setCurrentSpeed(effectiveBaseSpeed);
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [radius, effectiveBaseSpeed, isLocked]);

  // Continuous movement ticker (100ms ticks = 10Hz updates for high precision)
  useEffect(() => {
    if (activeIntervalRef.current) {
      clearInterval(activeIntervalRef.current);
      activeIntervalRef.current = null;
    }

    if (currentBearing !== null && currentSpeed > 0) {
      // If user hasn't toggled spoof session on yet, auto-engage
      if (!isSpoofing) {
        onStartSpoofing();
      }

      // Distance moved in 100ms (0.1s): speed in km/h -> m/s / 10
      const tickDurationHours = 0.1 / 3600;
      const distanceMeters = (currentSpeed * 1000) * tickDurationHours;

      activeIntervalRef.current = window.setInterval(() => {
        onStepMove(currentBearing, distanceMeters, currentSpeed);
      }, 100);
    }

    return () => {
      if (activeIntervalRef.current) {
        clearInterval(activeIntervalRef.current);
      }
    };
  }, [currentBearing, currentSpeed, isSpoofing, onStepMove, onStartSpoofing]);

  return (
    <div className="bg-slate-900/90 backdrop-blur-xl border border-white/10 p-3.5 rounded-3xl shadow-2xl flex flex-col items-center select-none w-72 max-w-full">
      {/* Mode Selector Tabs */}
      <div className="grid grid-cols-5 gap-1 w-full bg-slate-950/60 p-1 rounded-2xl mb-3 border border-white/5">
        {(['walk', 'run', 'cycle', 'drive', 'custom'] as TravelMode[]).map((mode) => {
          const cfg = TRAVEL_MODES[mode];
          const active = currentMode === mode;
          return (
            <button
              key={mode}
              onClick={() => onModeChange(mode)}
              title={`${cfg.name} (${mode === 'custom' ? customSpeedKmh : cfg.defaultSpeedKmh} km/h)`}
              className={`flex flex-col items-center justify-center py-1.5 rounded-xl text-[10px] font-medium transition-all ${
                active
                  ? 'bg-cyan-500 text-white shadow-md shadow-cyan-500/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-white/5'
              }`}
            >
              {mode === 'walk' && <Footprints className="w-3.5 h-3.5 mb-0.5" />}
              {mode === 'run' && <Zap className="w-3.5 h-3.5 mb-0.5" />}
              {mode === 'cycle' && <Bike className="w-3.5 h-3.5 mb-0.5" />}
              {mode === 'drive' && <Car className="w-3.5 h-3.5 mb-0.5" />}
              {mode === 'custom' && <Sliders className="w-3.5 h-3.5 mb-0.5" />}
              <span>{cfg.name}</span>
            </button>
          );
        })}
      </div>

      {/* Custom Speed Slider if Custom Mode is Selected */}
      {currentMode === 'custom' && (
        <div className="w-full mb-3 px-1">
          <div className="flex justify-between text-xs text-slate-400 mb-1">
            <span>Custom Speed</span>
            <span className="font-mono text-cyan-400 font-semibold">{customSpeedKmh.toFixed(1)} km/h</span>
          </div>
          <input
            type="range"
            min="1"
            max="120"
            step="0.5"
            value={customSpeedKmh}
            onChange={(e) => onCustomSpeedChange(parseFloat(e.target.value))}
            className="w-full accent-cyan-400 h-1.5 bg-slate-800 rounded-lg cursor-pointer"
          />
        </div>
      )}

      {/* Analog Joystick Disc */}
      <div className="relative flex items-center justify-center my-1">
        {/* Cardinal Markers */}
        <span className="absolute -top-3 text-[10px] font-mono text-slate-500 font-bold">N</span>
        <span className="absolute -bottom-3 text-[10px] font-mono text-slate-500 font-bold">S</span>
        <span className="absolute -left-3 text-[10px] font-mono text-slate-500 font-bold">W</span>
        <span className="absolute -right-3 text-[10px] font-mono text-slate-500 font-bold">E</span>

        <div
          ref={containerRef}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerUp}
          className="relative w-36 h-36 rounded-full bg-gradient-to-b from-slate-950 to-slate-900 border-2 border-slate-700/60 shadow-inner flex items-center justify-center cursor-grab active:cursor-grabbing touch-none"
        >
          {/* Concentric rings */}
          <div className="w-24 h-24 rounded-full border border-slate-800/80 pointer-events-none" />
          <div className="w-12 h-12 rounded-full border border-slate-800/50 pointer-events-none absolute" />

          {/* Draggable Knob */}
          <div
            className="absolute w-14 h-14 rounded-full bg-gradient-to-br from-slate-700 to-slate-800 border-2 border-cyan-400/80 shadow-[0_4px_16px_rgba(6,182,212,0.35)] flex items-center justify-center transition-transform pointer-events-none"
            style={{
              transform: `translate(${knobPos.x}px, ${knobPos.y}px)`,
              transition: isDragging ? 'none' : 'transform 0.15s cubic-bezier(0.175, 0.885, 0.32, 1.275)',
            }}
          >
            <div className="w-4 h-4 rounded-full bg-cyan-400 shadow-[0_0_8px_#22d3ee] flex items-center justify-center">
              {currentBearing !== null && (
                <div
                  className="w-0 h-0 border-l-[3px] border-l-transparent border-r-[3px] border-r-transparent border-b-[6px] border-b-white transform -translate-y-1"
                  style={{ transform: `rotate(${currentBearing}deg)` }}
                />
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Status & Lock Controls */}
      <div className="flex items-center justify-between w-full mt-3 pt-2 border-t border-white/5 text-xs">
        <div className="flex items-center gap-1.5 text-slate-300">
          <Compass className="w-3.5 h-3.5 text-cyan-400" />
          <span className="font-mono">{currentBearing !== null ? `${Math.round(currentBearing)}°` : '0°'}</span>
          <span className="text-slate-500">•</span>
          <span className="font-mono text-cyan-400 font-medium">{currentSpeed > 0 ? `${currentSpeed.toFixed(1)} km/h` : '0.0 km/h'}</span>
        </div>

        <button
          onClick={() => {
            if (isLocked) {
              setIsLocked(false);
              setKnobPos({ x: 0, y: 0 });
              setCurrentBearing(null);
              setCurrentSpeed(0);
            } else if (currentBearing !== null) {
              setIsLocked(true);
            }
          }}
          title={isLocked ? 'Unlock continuous movement' : 'Lock heading direction'}
          className={`flex items-center gap-1 px-2.5 py-1 rounded-xl text-[11px] font-medium border transition-all ${
            isLocked
              ? 'bg-amber-500/20 text-amber-300 border-amber-500/40'
              : 'bg-slate-800/80 text-slate-400 border-white/5 hover:text-slate-200'
          }`}
        >
          {isLocked ? <Lock className="w-3 h-3 text-amber-400" /> : <Unlock className="w-3 h-3" />}
          <span>{isLocked ? 'Locked' : 'Lock'}</span>
        </button>
      </div>
    </div>
  );
};
