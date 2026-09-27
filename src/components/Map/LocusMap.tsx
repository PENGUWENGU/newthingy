import React, { useEffect, useRef, useState } from 'react';
import L from 'leaflet';
import { Coordinate, SimulatedRoute, Waypoint } from '../../types';
import { Compass, Layers, MapPin, Navigation, Plus, Target } from 'lucide-react';

interface LocusMapProps {
  currentLocation: Coordinate;
  targetPin: Coordinate | null;
  activeRoute: SimulatedRoute | null;
  routeProgressIndex: number;
  isSpoofing: boolean;
  onMapClick: (coord: Coordinate) => void;
  onAddWaypoint?: (coord: Coordinate) => void;
  is3DMode: boolean;
  onToggle3D: () => void;
}

export const LocusMap: React.FC<LocusMapProps> = ({
  currentLocation,
  targetPin,
  activeRoute,
  routeProgressIndex,
  isSpoofing,
  onMapClick,
  onAddWaypoint,
  is3DMode,
  onToggle3D,
}) => {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<L.Map | null>(null);
  const userMarkerRef = useRef<L.Marker | null>(null);
  const targetMarkerRef = useRef<L.Marker | null>(null);
  const routePolylineRef = useRef<L.Polyline | null>(null);
  const completedPolylineRef = useRef<L.Polyline | null>(null);
  const waypointMarkersRef = useRef<L.Marker[]>([]);
  const [mapLayer, setMapLayer] = useState<'dark' | 'satellite' | 'street'>('dark');
  const tileLayerRef = useRef<L.TileLayer | null>(null);

  // Initialize Map
  useEffect(() => {
    if (!mapContainerRef.current || mapInstanceRef.current) return;

    const map = L.map(mapContainerRef.current, {
      center: [currentLocation.latitude, currentLocation.longitude],
      zoom: 16,
      zoomControl: false,
      attributionControl: true,
    });

    // Add Dark tiles by default
    const darkTiles = L.tileLayer(
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      {
        attribution: '&copy; <a href="https://carto.com/">CARTO</a>, OpenStreetMap',
        maxZoom: 20,
        subdomains: 'abcd',
      }
    ).addTo(map);

    tileLayerRef.current = darkTiles;
    mapInstanceRef.current = map;

    // Handle Map click
    map.on('click', (e: L.LeafletMouseEvent) => {
      onMapClick({
        latitude: e.latlng.lat,
        longitude: e.latlng.lng,
        altitude: 15,
        speedKmh: 0,
        accuracyMeters: 5,
      });
    });

    return () => {
      map.remove();
      mapInstanceRef.current = null;
    };
  }, []);

  // Update map tile layer style
  useEffect(() => {
    if (!mapInstanceRef.current || !tileLayerRef.current) return;

    mapInstanceRef.current.removeLayer(tileLayerRef.current);

    let url = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    let attribution = '&copy; CARTO, OpenStreetMap';

    if (mapLayer === 'satellite') {
      url = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      attribution = '&copy; Esri, Maxar, Earthstar';
    } else if (mapLayer === 'street') {
      url = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
      attribution = '&copy; OpenStreetMap contributors';
    }

    const newLayer = L.tileLayer(url, {
      attribution,
      maxZoom: 19,
      subdomains: mapLayer === 'street' ? 'abc' : 'abcd',
    }).addTo(mapInstanceRef.current);

    tileLayerRef.current = newLayer;
  }, [mapLayer]);

  // Update User Location Marker (Pulse + Directional Cone)
  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const map = mapInstanceRef.current;

    const heading = currentLocation.heading || 0;
    const speed = currentLocation.speedKmh || 0;

    const customUserHtml = `
      <div class="relative flex items-center justify-center -translate-x-1/2 -translate-y-1/2 pointer-events-none">
        <!-- Pulse effect when spoofing -->
        <div class="absolute w-12 h-12 rounded-full ${isSpoofing ? 'bg-cyan-500/25 pulse-ring' : 'bg-blue-500/10'}"></div>
        <!-- Directional cone -->
        <div class="absolute w-16 h-16 pointer-events-none transition-transform duration-200" style="transform: rotate(${heading}deg);">
          <div class="w-0 h-0 border-l-[8px] border-l-transparent border-r-[8px] border-r-transparent border-b-[20px] ${isSpoofing ? 'border-b-cyan-400/50' : 'border-b-blue-400/40'} mx-auto -translate-y-2"></div>
        </div>
        <!-- Central Dot -->
        <div class="relative w-6 h-6 rounded-full border-2 border-white ${isSpoofing ? 'bg-cyan-500 shadow-[0_0_15px_#06b6d4]' : 'bg-blue-600 shadow-md'} flex items-center justify-center transition-all duration-150">
          <div class="w-2 h-2 rounded-full bg-white"></div>
        </div>
      </div>
    `;

    const userIcon = L.divIcon({
      className: 'custom-user-marker',
      html: customUserHtml,
      iconSize: [24, 24],
      iconAnchor: [12, 12],
    });

    if (!userMarkerRef.current) {
      userMarkerRef.current = L.marker([currentLocation.latitude, currentLocation.longitude], {
        icon: userIcon,
        zIndexOffset: 1000,
      }).addTo(map);
    } else {
      userMarkerRef.current.setLatLng([currentLocation.latitude, currentLocation.longitude]);
      userMarkerRef.current.setIcon(userIcon);
    }
  }, [currentLocation, isSpoofing]);

  // Update Target Pin Marker
  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const map = mapInstanceRef.current;

    if (!targetPin) {
      if (targetMarkerRef.current) {
        map.removeLayer(targetMarkerRef.current);
        targetMarkerRef.current = null;
      }
      return;
    }

    const pinHtml = `
      <div class="relative -translate-x-1/2 -translate-y-full cursor-pointer group">
        <div class="bg-gradient-to-b from-rose-500 to-rose-600 text-white p-2 rounded-full shadow-[0_4px_16px_rgba(244,63,94,0.6)] border border-rose-300 flex items-center justify-center transform transition-transform group-hover:scale-110">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
        </div>
        <div class="w-2 h-2 bg-rose-600 rounded-full mx-auto -mt-1 shadow-sm"></div>
      </div>
    `;

    const pinIcon = L.divIcon({
      className: 'custom-target-marker',
      html: pinHtml,
      iconSize: [32, 32],
      iconAnchor: [16, 32],
    });

    if (!targetMarkerRef.current) {
      targetMarkerRef.current = L.marker([targetPin.latitude, targetPin.longitude], {
        icon: pinIcon,
        zIndexOffset: 900,
      }).addTo(map);
    } else {
      targetMarkerRef.current.setLatLng([targetPin.latitude, targetPin.longitude]);
      targetMarkerRef.current.setIcon(pinIcon);
    }
  }, [targetPin]);

  // Update Route Polyline & Waypoints
  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const map = mapInstanceRef.current;

    // Clear old waypoints
    waypointMarkersRef.current.forEach((m) => map.removeLayer(m));
    waypointMarkersRef.current = [];

    // Clear old polylines
    if (routePolylineRef.current) {
      map.removeLayer(routePolylineRef.current);
      routePolylineRef.current = null;
    }
    if (completedPolylineRef.current) {
      map.removeLayer(completedPolylineRef.current);
      completedPolylineRef.current = null;
    }

    if (!activeRoute || activeRoute.pathCoordinates.length === 0) return;

    // Add full route path polyline (dotted cyan / slate)
    const polyline = L.polyline(activeRoute.pathCoordinates, {
      color: '#38bdf8',
      weight: 4,
      opacity: 0.75,
      dashArray: '8, 8',
      lineCap: 'round',
      lineJoin: 'round',
    }).addTo(map);

    routePolylineRef.current = polyline;

    // Add completed portion polyline if in progress
    if (routeProgressIndex > 0) {
      const completedCoords = activeRoute.pathCoordinates.slice(0, routeProgressIndex + 1);
      const completedPoly = L.polyline(completedCoords, {
        color: '#10b981',
        weight: 5,
        opacity: 0.95,
        lineCap: 'round',
      }).addTo(map);
      completedPolylineRef.current = completedPoly;
    }

    // Add Waypoint markers
    activeRoute.waypoints.forEach((wpt, index) => {
      const isStart = index === 0;
      const isEnd = index === activeRoute.waypoints.length - 1;
      const color = isStart ? 'bg-emerald-500' : isEnd ? 'bg-rose-500' : 'bg-cyan-600';
      const label = isStart ? 'A' : isEnd ? 'B' : `${index + 1}`;

      const wptHtml = `
        <div class="relative -translate-x-1/2 -translate-y-1/2">
          <div class="${color} text-white font-bold text-[11px] w-6 h-6 rounded-full flex items-center justify-center shadow-lg border-2 border-slate-900 ring-2 ring-white/30">
            ${label}
          </div>
        </div>
      `;

      const wptIcon = L.divIcon({
        className: 'custom-wpt-marker',
        html: wptHtml,
        iconSize: [24, 24],
        iconAnchor: [12, 12],
      });

      const marker = L.marker([wpt.latitude, wpt.longitude], {
        icon: wptIcon,
        zIndexOffset: 800,
      }).addTo(map);

      waypointMarkersRef.current.push(marker);
    });
  }, [activeRoute, routeProgressIndex]);

  // Center on current location
  const handleRecenter = () => {
    if (mapInstanceRef.current) {
      mapInstanceRef.current.flyTo([currentLocation.latitude, currentLocation.longitude], 17, {
        duration: 0.8,
      });
    }
  };

  return (
    <div className={`relative w-full h-full overflow-hidden transition-all duration-500 ${is3DMode ? 'perspective-3d' : ''}`}>
      <style>{`
        .perspective-3d .leaflet-container {
          transform: rotateX(28deg) scale(1.06);
          transform-origin: 50% 65%;
          transition: transform 0.4s ease;
        }
      `}</style>
      
      <div ref={mapContainerRef} className="w-full h-full" />

      {/* Map Action Floating Controls (Top Right) */}
      <div className="absolute top-20 right-4 z-[400] flex flex-col gap-2.5">
        {/* Recenter button */}
        <button
          onClick={handleRecenter}
          title="Center on Location"
          className="w-11 h-11 bg-slate-900/90 backdrop-blur-md hover:bg-slate-800 text-white rounded-2xl flex items-center justify-center shadow-xl border border-white/10 active:scale-95 transition-all"
        >
          <Navigation className="w-5 h-5 text-cyan-400" />
        </button>

        {/* 3D View Toggle */}
        <button
          onClick={onToggle3D}
          title="Toggle 3D Perspective"
          className={`w-11 h-11 backdrop-blur-md rounded-2xl flex items-center justify-center shadow-xl border active:scale-95 transition-all ${
            is3DMode
              ? 'bg-cyan-500 text-white border-cyan-300 shadow-[0_0_12px_rgba(6,182,212,0.4)]'
              : 'bg-slate-900/90 hover:bg-slate-800 text-slate-300 border-white/10'
          }`}
        >
          <span className="text-xs font-bold font-mono">3D</span>
        </button>

        {/* Layer Switcher */}
        <div className="relative group">
          <button
            onClick={() => {
              setMapLayer((prev) => (prev === 'dark' ? 'satellite' : prev === 'satellite' ? 'street' : 'dark'));
            }}
            title="Switch Map Layer"
            className="w-11 h-11 bg-slate-900/90 backdrop-blur-md hover:bg-slate-800 text-slate-300 rounded-2xl flex items-center justify-center shadow-xl border border-white/10 active:scale-95 transition-all"
          >
            <Layers className="w-5 h-5 text-indigo-400" />
          </button>
          <div className="absolute right-12 top-0 px-2.5 py-1 rounded-lg bg-slate-900/95 text-[11px] text-slate-300 whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none border border-white/10 capitalize">
            {mapLayer} view
          </div>
        </div>
      </div>
    </div>
  );
};
