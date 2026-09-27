import { Coordinate, TravelMode, TravelModeConfig, SimulatedRoute, Waypoint } from '../types';

export const TRAVEL_MODES: Record<TravelMode, TravelModeConfig> = {
  walk: {
    id: 'walk',
    name: 'Walk',
    defaultSpeedKmh: 4.5,
    minSpeedKmh: 2.5,
    maxSpeedKmh: 6.0,
    speedJitterPct: 8,
    icon: 'Footprints',
  },
  run: {
    id: 'run',
    name: 'Run',
    defaultSpeedKmh: 10.5,
    minSpeedKmh: 7.0,
    maxSpeedKmh: 14.0,
    speedJitterPct: 10,
    icon: 'Zap',
  },
  cycle: {
    id: 'cycle',
    name: 'Cycle',
    defaultSpeedKmh: 20.0,
    minSpeedKmh: 12.0,
    maxSpeedKmh: 32.0,
    speedJitterPct: 12,
    icon: 'Bike',
  },
  drive: {
    id: 'drive',
    name: 'Drive',
    defaultSpeedKmh: 55.0,
    minSpeedKmh: 25.0,
    maxSpeedKmh: 120.0,
    speedJitterPct: 15,
    icon: 'Car',
  },
  custom: {
    id: 'custom',
    name: 'Custom',
    defaultSpeedKmh: 15.0,
    minSpeedKmh: 1.0,
    maxSpeedKmh: 250.0,
    speedJitterPct: 5,
    icon: 'Sliders',
  },
};

/** Convert degrees to radians */
export const toRad = (deg: number): number => (deg * Math.PI) / 180;

/** Convert radians to degrees */
export const toDeg = (rad: number): number => (rad * 180) / Math.PI;

/** Calculate Great Circle distance in meters between two coordinates */
export function calculateDistanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371000; // Earth radius in meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/** Calculate compass bearing in degrees (0 - 360) from point A to point B */
export function calculateBearing(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δλ = toRad(lon2 - lon1);

  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x =
    Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  const θ = Math.atan2(y, x);
  return (toDeg(θ) + 360) % 360;
}

/** Compute destination point given start coordinate, distance in meters and bearing in degrees */
export function computeDestination(
  lat: number,
  lon: number,
  distanceMeters: number,
  bearingDeg: number
): { latitude: number; longitude: number } {
  const R = 6371000;
  const δ = distanceMeters / R;
  const θ = toRad(bearingDeg);
  const φ1 = toRad(lat);
  const λ1 = toRad(lon);

  const sinφ1 = Math.sin(φ1);
  const cosφ1 = Math.cos(φ1);
  const sinδ = Math.sin(δ);
  const cosδ = Math.cos(δ);

  const sinφ2 = sinφ1 * cosδ + cosφ1 * sinδ * Math.cos(θ);
  const φ2 = Math.asin(sinφ2);
  const y = Math.sin(θ) * sinδ * cosφ1;
  const x = cosδ - sinφ1 * sinφ2;
  const λ2 = λ1 + Math.atan2(y, x);

  return {
    latitude: toDeg(φ2),
    longitude: ((toDeg(λ2) + 540) % 360) - 180,
  };
}

/** Apply realistic speed jitter variation */
export function applySpeedJitter(baseSpeedKmh: number, jitterPct: number): number {
  const variation = (Math.random() * 2 - 1) * (jitterPct / 100);
  return Math.max(0.5, baseSpeedKmh * (1 + variation));
}

/** Interpolate high-resolution coordinates along a list of waypoints */
export function interpolateWaypoints(
  waypoints: Waypoint[],
  stepDistanceMeters: number = 8
): { path: [number, number][]; totalDistance: number } {
  if (waypoints.length < 2) {
    return {
      path: waypoints.map((w) => [w.latitude, w.longitude]),
      totalDistance: 0,
    };
  }

  const path: [number, number][] = [];
  let totalDistance = 0;

  for (let i = 0; i < waypoints.length - 1; i++) {
    const start = waypoints[i];
    const end = waypoints[i + 1];
    const segmentDist = calculateDistanceMeters(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude
    );
    totalDistance += segmentDist;

    const bearing = calculateBearing(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude
    );

    const steps = Math.max(1, Math.floor(segmentDist / stepDistanceMeters));
    for (let s = 0; s < steps; s++) {
      const dist = (segmentDist / steps) * s;
      const point = computeDestination(start.latitude, start.longitude, dist, bearing);
      path.push([point.latitude, point.longitude]);
    }
  }

  const last = waypoints[waypoints.length - 1];
  path.push([last.latitude, last.longitude]);

  return { path, totalDistance };
}

/** Generate standard GPX 1.1 XML string for exporting routes */
export function generateGPX(route: SimulatedRoute): string {
  const wptTags = route.waypoints
    .map(
      (w, idx) =>
        `    <wpt lat="${w.latitude.toFixed(7)}" lon="${w.longitude.toFixed(7)}">
      <name>${w.name || `Waypoint ${idx + 1}`}</name>
      <ele>${w.altitude || 10}</ele>
    </wpt>`
    )
    .join('\n');

  const trkptTags = route.pathCoordinates
    .map(
      ([lat, lon], idx) =>
        `      <trkpt lat="${lat.toFixed(7)}" lon="${lon.toFixed(7)}">
        <ele>10</ele>
        <time>${new Date(Date.now() + idx * 1000).toISOString()}</time>
      </trkpt>`
    )
    .join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Locus iOS Simulator - https://github.com/ChrisMack32/Locus" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>${route.name}</name>
    <desc>Locus simulated route for developer location teleport</desc>
    <time>${new Date().toISOString()}</time>
  </metadata>
${wptTags}
  <trk>
    <name>${route.name}</name>
    <trkseg>
${trkptTags}
    </trkseg>
  </trk>
</gpx>`;
}

/** Parse a GPX file into waypoints and coordinates */
export function parseGPX(gpxContent: string): { name: string; waypoints: Waypoint[]; coordinates: [number, number][] } {
  const parser = new DOMParser();
  const xmlDoc = parser.parseFromString(gpxContent, 'text/xml');

  let name = 'Imported Route';
  const nameNode = xmlDoc.querySelector('metadata > name, trk > name');
  if (nameNode?.textContent) {
    name = nameNode.textContent.trim();
  }

  const waypoints: Waypoint[] = [];
  const coordinates: [number, number][] = [];

  // Parse wpt elements
  const wptNodes = xmlDoc.querySelectorAll('wpt');
  wptNodes.forEach((node, idx) => {
    const lat = parseFloat(node.getAttribute('lat') || '0');
    const lon = parseFloat(node.getAttribute('lon') || '0');
    const ele = parseFloat(node.querySelector('ele')?.textContent || '10');
    const wptName = node.querySelector('name')?.textContent || `Point ${idx + 1}`;
    if (!isNaN(lat) && !isNaN(lon)) {
      waypoints.push({
        id: `wpt-${idx}-${Date.now()}`,
        name: wptName,
        latitude: lat,
        longitude: lon,
        altitude: ele,
      });
    }
  });

  // Parse trkpt elements
  const trkptNodes = xmlDoc.querySelectorAll('trkpt');
  trkptNodes.forEach((node) => {
    const lat = parseFloat(node.getAttribute('lat') || '0');
    const lon = parseFloat(node.getAttribute('lon') || '0');
    if (!isNaN(lat) && !isNaN(lon)) {
      coordinates.push([lat, lon]);
    }
  });

  // If no trackpoints but waypoints exist, construct coordinates
  if (coordinates.length === 0 && waypoints.length >= 2) {
    const { path } = interpolateWaypoints(waypoints);
    return { name, waypoints, coordinates: path };
  }

  // If no explicit waypoints but trackpoints exist, sample waypoints
  if (waypoints.length === 0 && coordinates.length > 0) {
    const sampled = [0, Math.floor(coordinates.length / 2), coordinates.length - 1];
    sampled.forEach((idx, i) => {
      const coord = coordinates[idx];
      if (coord) {
        waypoints.push({
          id: `wpt-gen-${i}`,
          name: i === 0 ? 'Start' : i === sampled.length - 1 ? 'End' : `Stop ${i}`,
          latitude: coord[0],
          longitude: coord[1],
        });
      }
    });
  }

  return { name, waypoints, coordinates };
}
