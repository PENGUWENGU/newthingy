import { TelemetryLog, PairingConfig, Coordinate } from '../types';

type LogListener = (log: TelemetryLog) => void;

class TunnelSimulator {
  private listeners: LogListener[] = [];
  private logs: TelemetryLog[] = [];
  private heartbeatTimer: number | null = null;
  private isConnected: boolean = true;
  private packetCount: number = 0;

  constructor() {
    this.addLog('info', 'Locus Engine initialized. DVT Location FFI ready.');
    this.startHeartbeat();
  }

  public subscribe(listener: LogListener): () => void {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  public getLogs(): TelemetryLog[] {
    return [...this.logs];
  }

  public getPacketCount(): number {
    return this.packetCount;
  }

  public addLog(level: TelemetryLog['level'], message: string, coordinates?: { lat: number; lng: number }) {
    const log: TelemetryLog = {
      id: `log-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      timestamp: new Date().toLocaleTimeString('en-US', { hour12: false }),
      level,
      message,
      coordinates,
    };
    this.logs = [log, ...this.logs.slice(0, 150)];
    this.listeners.forEach((l) => l(log));
  }

  public simulateInjectLocation(coord: Coordinate) {
    this.packetCount++;
    const latStr = coord.latitude.toFixed(6);
    const lngStr = coord.longitude.toFixed(6);
    const speedStr = coord.speedKmh ? `${coord.speedKmh.toFixed(1)} km/h` : '0 km/h';
    const hdgStr = coord.heading !== undefined ? `${Math.round(coord.heading)}°` : '0°';

    this.addLog(
      'success',
      `locationd payload injected: (${latStr}, ${lngStr}) | Spd: ${speedStr} | Hdg: ${hdgStr}`,
      { lat: coord.latitude, lng: coord.longitude }
    );
  }

  public simulateClearLocation() {
    this.addLog('warn', 'SimulateLocation::clear() sent. System GPS restored.');
  }

  private startHeartbeat() {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = window.setInterval(() => {
      if (this.isConnected) {
        this.packetCount += 1;
      }
    }, 4000);
  }

  public simulatePairingHandshake(config: Partial<PairingConfig>): Promise<boolean> {
    return new Promise((resolve) => {
      this.addLog('info', `Connecting to developer tunnel ${config.vpnHost || '10.7.0.1'}...`);
      setTimeout(() => {
        this.addLog('info', 'Discovered com.apple.dt.remotepairing on port 58783');
        setTimeout(() => {
          this.addLog('success', 'TLS handshake verified. RemotePairing session established.');
          resolve(true);
        }, 600);
      }, 500);
    });
  }
}

export const tunnelSimulator = new TunnelSimulator();
