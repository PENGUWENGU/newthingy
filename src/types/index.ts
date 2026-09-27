export type TravelMode = 'walk' | 'run' | 'cycle' | 'drive' | 'custom';

export interface TravelModeConfig {
  id: TravelMode;
  name: string;
  defaultSpeedKmh: number;
  minSpeedKmh: number;
  maxSpeedKmh: number;
  speedJitterPct: number; // speed variation simulation
  icon: string;
}

export interface Coordinate {
  latitude: number;
  longitude: number;
  altitude?: number;
  heading?: number;
  speedKmh?: number;
  accuracyMeters?: number;
  timestamp?: number;
}

export interface SavedPlace {
  id: string;
  name: string;
  coordinate: Coordinate;
  category: 'favorite' | 'recent' | 'custom';
  createdAt: number;
  notes?: string;
}

export interface Waypoint {
  id: string;
  name?: string;
  latitude: number;
  longitude: number;
  altitude?: number;
  pauseSeconds?: number;
}

export interface SimulatedRoute {
  id: string;
  name: string;
  waypoints: Waypoint[];
  pathCoordinates: [number, number][]; // high resolution interpolated path
  totalDistanceMeters: number;
  estimatedDurationSeconds: number;
  mode: TravelMode;
  loop: boolean;
  reverseOnEnd: boolean;
}

export type SpoofStatus = 'disconnected' | 'idle' | 'spoofing' | 'paused';

export interface TelemetryLog {
  id: string;
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
  coordinates?: { lat: number; lng: number };
}

export interface PairingConfig {
  paired: boolean;
  pairingType: 'rppairing' | 'bonjour_ios27' | 'manual';
  pairingHost: string;
  pairingPort: number;
  vpnHost: string;
  vpnConnected: boolean;
  deviceId: string;
  deviceName: string;
  iosVersion: string;
  keepAliveAudio: boolean;
  keepAliveBgLocation: boolean;
}
