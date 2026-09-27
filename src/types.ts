export type MovementMode = 'walk' | 'run' | 'cycle' | 'drive' | 'custom';

export interface Coordinates {
  lat: number;
  lng: number;
  alt?: number;
  speed?: number; // m/s
  heading?: number; // degrees
  accuracy?: number; // meters
}

export interface FavoritePlace {
  id: string;
  name: string;
  category: 'landmark' | 'gaming' | 'custom' | 'scenic';
  lat: number;
  lng: number;
  alt?: number;
  notes?: string;
  createdAt: number;
}

export interface RouteWaypoint {
  id: string;
  lat: number;
  lng: number;
  name?: string;
}

export interface RouteConfig {
  id: string;
  name: string;
  mode: MovementMode;
  waypoints: RouteWaypoint[];
  interpolatedPoints: Coordinates[];
  totalDistanceMeters: number;
  estimatedDurationSeconds: number;
  loop: boolean;
  bounce: boolean;
  reverse?: boolean;
}

export type SpoofStatus = 'disconnected' | 'ready' | 'spoofing' | 'routing';

export interface MapLayerConfig {
  id: 'dark' | 'standard' | 'satellite' | 'terrain';
  name: string;
  url: string;
  attribution: string;
  maxZoom: number;
}

export interface SimulationSettings {
  movementMode: MovementMode;
  speeds: {
    walk: number; // km/h
    run: number;
    cycle: number;
    drive: number;
    custom: number;
  };
  jitterEnabled: boolean;
  jitterAmountMeters: number; // slight GPS realistic jitter
  simulatedAltitudeMeters: number;
  simulatedAccuracyMeters: number;
  loopbackTunnelIp: string;
  developerPairingCode: string;
  isTunnelActive: boolean;
  isDvtConnected: boolean;
}
