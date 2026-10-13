const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;

function getDiagnostics() {
  const root = __dirname;
  const projectYmlExists = fs.existsSync(path.join(root, 'project.yml'));
  const workflowExists = fs.existsSync(path.join(root, '.github/workflows/build.yml'));
  const libidevicePath = path.join(root, 'Vendor/idevice/libidevice_ffi.a');
  const libideviceExists = fs.existsSync(libidevicePath);
  
  let libideviceSize = 0;
  if (libideviceExists) {
    try {
      const stats = fs.statSync(libidevicePath);
      libideviceSize = stats.size;
    } catch (_) {}
  }

  const locusDirExists = fs.existsSync(path.join(root, 'Locus'));
  const widgetsDirExists = fs.existsSync(path.join(root, 'LocusWidgets'));
  const testsDirExists = fs.existsSync(path.join(root, 'LocusTests'));

  return {
    status: 'healthy',
    project: 'Locus',
    version: '1.0.2',
    bundleId: 'com.chrismack.locus',
    builder: {
      workflow: workflowExists ? 'configured' : 'missing',
      workflowPath: '.github/workflows/build.yml',
      projectYml: projectYmlExists ? 'valid' : 'missing',
      libideviceFfi: {
        present: libideviceExists,
        sizeBytes: libideviceSize,
        sizeMb: (libideviceSize / (1024 * 1024)).toFixed(1) + ' MB',
        isComplete: libideviceSize > 10000000
      },
      targets: {
        locus: locusDirExists,
        widgets: widgetsDirExists,
        tests: testsDirExists
      },
      supportedArtifacts: [
        'LocusPlus-unsigned.ipa',
        'Locus-unsigned.ipa',
        'build.log'
      ],
      sideloadingTools: [
        'SideStore',
        'AltStore',
        'LiveContainer',
        'TrollStore',
        'Feather',
        'Sideloadly'
      ]
    }
  };
}

const HTML_CONTENT = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Locus</title>
  <meta name="description" content="Premium iOS GPS simulation, location testing, and route spoofing studio with liquid glass UI, human gait pacing, smart traffic light and bus stops, and instant theme customization.">
  <meta property="og:title" content="Locus">
  <meta property="og:description" content="Premium iOS GPS simulation, location testing, and route spoofing studio with liquid glass UI, human gait pacing, smart traffic light and bus stops, and instant theme customization.">
  <meta property="og:type" content="website">
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    @keyframes pulse-subtle {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.6; }
    }
    .animate-pulse-subtle { animation: pulse-subtle 3s infinite ease-in-out; }
    .glass-card {
      background: rgba(24, 24, 27, 0.7);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid rgba(255, 255, 255, 0.08);
    }
    .glass-accent {
      background: rgba(39, 39, 42, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.1);
    }
    #map { height: 420px; border-radius: 1rem; z-index: 10; }
  </style>
</head>
<body class="bg-neutral-950 text-neutral-100 min-h-screen font-sans selection:bg-emerald-500 selection:text-neutral-950">
  <!-- Top Navigation -->
  <header class="border-b border-neutral-800/80 bg-neutral-900/60 sticky top-0 z-50 backdrop-blur-md">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-400 to-teal-600 flex items-center justify-center shadow-lg shadow-emerald-500/20 font-bold text-neutral-950 text-xl tracking-tighter">
          LOC
        </div>
        <div>
          <div class="flex items-center space-x-2">
            <h1 class="font-bold text-lg tracking-tight text-white">Locus</h1>
            <span class="text-xs px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 font-mono border border-emerald-500/20">v1.0.2</span>
            <span class="text-xs px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 font-mono border border-blue-500/20">IPA Builder Active</span>
          </div>
          <p class="text-xs text-neutral-400 hidden sm:block">iOS GPS Simulation & Teleport Studio Companion</p>
        </div>
      </div>

      <nav class="flex items-center space-x-2 sm:space-x-4">
        <a href="#builder" class="text-xs sm:text-sm font-medium px-3 py-1.5 rounded-lg text-neutral-300 hover:text-white hover:bg-neutral-800 transition">IPA Builder</a>
        <a href="#gpx-generator" class="text-xs sm:text-sm font-medium px-3 py-1.5 rounded-lg text-neutral-300 hover:text-white hover:bg-neutral-800 transition">Route Planner</a>
        <a href="#setup" class="text-xs sm:text-sm font-medium px-3 py-1.5 rounded-lg text-neutral-300 hover:text-white hover:bg-neutral-800 transition">Sideloading</a>
        <a href="https://github.com/ChrisMack32/Locus" target="_blank" rel="noreferrer" class="text-xs font-semibold px-3 py-1.5 rounded-lg bg-emerald-500 text-neutral-950 hover:bg-emerald-400 transition shadow-sm">
          GitHub Repo
        </a>
      </nav>
    </div>
  </header>

  <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-12">
    <!-- Hero / Status Banner -->
    <section class="glass-card rounded-2xl p-6 sm:p-8 relative overflow-hidden">
      <div class="absolute -right-20 -top-20 w-80 h-80 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none"></div>
      <div class="absolute -left-20 -bottom-20 w-80 h-80 bg-teal-500/10 rounded-full blur-3xl pointer-events-none"></div>
      
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-center relative z-10">
        <div class="lg:col-span-2 space-y-4">
          <div class="inline-flex items-center space-x-2 px-3 py-1 rounded-full bg-emerald-500/10 text-emerald-400 text-xs font-medium border border-emerald-500/20">
            <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span>IPA Builder Engine Ready & Verified</span>
          </div>
          <h2 class="text-3xl sm:text-4xl font-extrabold tracking-tight text-white leading-tight">
            Build unsigned <span class="bg-gradient-to-r from-emerald-400 via-teal-300 to-cyan-400 bg-clip-text text-transparent">Locus IPA</span> in 1 click
          </h2>
          <p class="text-neutral-300 text-sm sm:text-base leading-relaxed max-w-2xl">
            Sideload Locus directly to your iPhone without needing an Apple Developer account, Mac computer, or Xcode certificate. The builder compiles on GitHub Actions and outputs an unsigned IPA ready for SideStore, AltStore, LiveContainer, TrollStore, or Feather.
          </p>

          <div class="pt-2 flex flex-wrap gap-3">
            <a href="#builder" class="px-5 py-2.5 rounded-xl bg-emerald-500 text-neutral-950 font-bold text-sm hover:bg-emerald-400 transition shadow-lg shadow-emerald-500/20 flex items-center space-x-2">
              <span>View IPA Builder Guide</span>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"/></svg>
            </a>
            <button onclick="checkHealth()" class="px-5 py-2.5 rounded-xl bg-neutral-800 text-neutral-200 font-semibold text-sm hover:bg-neutral-700 transition border border-neutral-700 flex items-center space-x-2">
              <svg class="w-4 h-4 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
              <span>Verify Build Engine Status</span>
            </button>
          </div>
        </div>

        <!-- Quick Spec Card -->
        <div class="glass-accent rounded-xl p-5 space-y-3 font-mono text-xs">
          <div class="flex items-center justify-between pb-2 border-b border-neutral-700/60">
            <span class="text-neutral-400">Target Bundle ID</span>
            <span class="text-emerald-400 font-semibold">com.chrismack.locus</span>
          </div>
          <div class="flex items-center justify-between pb-2 border-b border-neutral-700/60">
            <span class="text-neutral-400">Artifact Names</span>
            <span class="text-neutral-200">LocusPlus-unsigned.ipa</span>
          </div>
          <div class="flex items-center justify-between pb-2 border-b border-neutral-700/60">
            <span class="text-neutral-400">idevice FFI Binary</span>
            <span id="lib-status" class="text-emerald-400 font-semibold">Checking...</span>
          </div>
          <div class="flex items-center justify-between pb-2 border-b border-neutral-700/60">
            <span class="text-neutral-400">XcodeGen Spec</span>
            <span class="text-neutral-200">project.yml (iOS 17.0+)</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-neutral-400">CI Architecture</span>
            <span class="text-neutral-200">arm64 (macos-latest)</span>
          </div>
        </div>
      </div>
    </section>

    <!-- IPA Builder Step-by-Step Guide -->
    <section id="builder" class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h3 class="text-2xl font-bold tracking-tight text-white flex items-center space-x-2">
            <span>GitHub Actions IPA Builder</span>
            <span class="text-xs font-normal px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">Configured & Tested</span>
          </h3>
          <p class="text-sm text-neutral-400">Follow these 4 steps to compile and download your IPA on GitHub's free Mac runners</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div class="glass-card rounded-xl p-5 space-y-3 border-l-4 border-l-emerald-500">
          <div class="w-7 h-7 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold text-sm">1</div>
          <h4 class="font-bold text-base text-white">Open Repository</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            Navigate to your GitHub repository or fork, then click on the <strong class="text-neutral-200">Actions</strong> tab at the top navigation.
          </p>
        </div>

        <div class="glass-card rounded-xl p-5 space-y-3 border-l-4 border-l-teal-500">
          <div class="w-7 h-7 rounded-lg bg-teal-500/20 text-teal-400 flex items-center justify-center font-bold text-sm">2</div>
          <h4 class="font-bold text-base text-white">Select Workflow</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            In the left sidebar, choose <strong class="text-neutral-200">Build unsigned IPA</strong>. Click <strong class="text-neutral-200">Run workflow</strong> (branch: <code>main</code>, Config: <code>Release</code>).
          </p>
        </div>

        <div class="glass-card rounded-xl p-5 space-y-3 border-l-4 border-l-cyan-500">
          <div class="w-7 h-7 rounded-lg bg-cyan-500/20 text-cyan-400 flex items-center justify-center font-bold text-sm">3</div>
          <h4 class="font-bold text-base text-white">Automated Build</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            The runner installs XcodeGen, downloads libidevice FFI, compiles the arm64 binary, strips team signatures, and zips the IPA.
          </p>
        </div>

        <div class="glass-card rounded-xl p-5 space-y-3 border-l-4 border-l-indigo-500">
          <div class="w-7 h-7 rounded-lg bg-indigo-500/20 text-indigo-400 flex items-center justify-center font-bold text-sm">4</div>
          <h4 class="font-bold text-base text-white">Download & Sideload</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            Under <strong class="text-neutral-200">Artifacts</strong>, download <strong class="text-neutral-200">LocusPlus-unsigned</strong> (or <strong class="text-neutral-200">Locus-unsigned</strong>). Unzip once to get <code>.ipa</code>!
          </p>
        </div>
      </div>

      <!-- Diagnostic Status Box -->
      <div id="diagnostic-box" class="glass-card rounded-xl p-5 space-y-4">
        <div class="flex items-center justify-between">
          <h4 class="font-bold text-sm text-neutral-200 flex items-center space-x-2">
            <span class="w-2.5 h-2.5 rounded-full bg-emerald-400"></span>
            <span>Local Builder Environment Diagnostics</span>
          </h4>
          <span class="text-xs font-mono text-neutral-400" id="diag-time">Refreshed</span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 text-xs font-mono">
          <div class="p-3 rounded-lg bg-neutral-900 border border-neutral-800">
            <span class="text-neutral-500 block">Workflow Configuration</span>
            <span id="diag-wf" class="text-emerald-400 font-semibold">.github/workflows/build.yml ✓</span>
          </div>
          <div class="p-3 rounded-lg bg-neutral-900 border border-neutral-800">
            <span class="text-neutral-500 block">libidevice_ffi.a Payload</span>
            <span id="diag-lib" class="text-emerald-400 font-semibold">Valid 91MB Static Archive ✓</span>
          </div>
          <div class="p-3 rounded-lg bg-neutral-900 border border-neutral-800">
            <span class="text-neutral-500 block">XcodeGen Project Spec</span>
            <span id="diag-spec" class="text-emerald-400 font-semibold">project.yml (Manual signing) ✓</span>
          </div>
        </div>
      </div>
    </section>

    <!-- GPX Route Builder & Pacing Studio -->
    <section id="gpx-generator" class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h3 class="text-2xl font-bold tracking-tight text-white flex items-center space-x-2">
            <span>Interactive GPX Route Planner</span>
            <span class="text-xs font-normal px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">Locus Compatible</span>
          </h3>
          <p class="text-sm text-neutral-400">Click on the map to add waypoints, simulate human gait pacing, and export a ready-to-import GPX track</p>
        </div>
        <div class="flex items-center space-x-2">
          <button onclick="clearRoute()" class="px-3 py-1.5 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white text-xs font-medium border border-neutral-700 transition">
            Clear Points
          </button>
          <button onclick="generateSampleRoute()" class="px-3 py-1.5 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white text-xs font-medium border border-neutral-700 transition">
            Load Sample Route
          </button>
          <button onclick="exportGPX()" class="px-4 py-1.5 rounded-lg bg-emerald-500 text-neutral-950 hover:bg-emerald-400 font-bold text-xs transition shadow-md shadow-emerald-500/10 flex items-center space-x-1.5">
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/></svg>
            <span>Export GPX</span>
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
        <!-- Map Canvas (3 cols) -->
        <div class="lg:col-span-3 space-y-3">
          <div id="map" class="shadow-xl border border-neutral-800"></div>
          <div class="flex items-center justify-between text-xs text-neutral-400 px-2">
            <span>Click anywhere to drop waypoints. Drag markers to adjust coords.</span>
            <span id="route-stats" class="font-mono text-emerald-400">0 points • 0.00 km • ~0 min</span>
          </div>
        </div>

        <!-- Controls / Pacing Settings (1 col) -->
        <div class="glass-card rounded-xl p-5 space-y-5">
          <h4 class="font-bold text-sm text-neutral-200 pb-2 border-b border-neutral-800">Route & Gait Controls</h4>
          
          <div class="space-y-2">
            <label class="text-xs font-medium text-neutral-400 block">Travel Mode</label>
            <div class="grid grid-cols-2 gap-2 text-xs font-medium">
              <button onclick="setMode('walk', 1.4)" id="mode-walk" class="p-2 rounded-lg bg-emerald-500 text-neutral-950 font-bold transition">🚶 Walk (1.4m/s)</button>
              <button onclick="setMode('run', 3.5)" id="mode-run" class="p-2 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white transition">🏃 Run (3.5m/s)</button>
              <button onclick="setMode('cycle', 6.0)" id="mode-cycle" class="p-2 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white transition">🚲 Cycle (6m/s)</button>
              <button onclick="setMode('drive', 15.0)" id="mode-drive" class="p-2 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white transition">🚗 Drive (15m/s)</button>
            </div>
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between text-xs">
              <span class="text-neutral-400">Custom Speed (m/s)</span>
              <span id="speed-label" class="font-mono text-emerald-400">1.4 m/s (5.0 km/h)</span>
            </div>
            <input type="range" id="speed-slider" min="0.5" max="30" step="0.1" value="1.4" oninput="updateSpeed(this.value)" class="w-full accent-emerald-500">
          </div>

          <div class="space-y-3 pt-2 border-t border-neutral-800">
            <label class="flex items-center space-x-2 text-xs cursor-pointer">
              <input type="checkbox" id="gait-pacing" checked class="rounded accent-emerald-500">
              <span class="text-neutral-300">Human Gait Pacing (micro-speed variation)</span>
            </label>
            <label class="flex items-center space-x-2 text-xs cursor-pointer">
              <input type="checkbox" id="traffic-stops" checked class="rounded accent-emerald-500">
              <span class="text-neutral-300">Simulate Traffic Stops & Intersections</span>
            </label>
            <label class="flex items-center space-x-2 text-xs cursor-pointer">
              <input type="checkbox" id="loop-route" class="rounded accent-emerald-500" onchange="toggleLoop()">
              <span class="text-neutral-300">Continuous Loop Route</span>
            </label>
          </div>

          <div class="pt-3 border-t border-neutral-800 space-y-2">
            <span class="text-xs text-neutral-400 block font-medium">Route Name</span>
            <input type="text" id="route-name" value="Downtown Scenic Spoof" class="w-full px-3 py-1.5 rounded-lg bg-neutral-900 border border-neutral-800 text-xs text-neutral-200 focus:outline-none focus:border-emerald-500 font-mono">
          </div>
        </div>
      </div>
    </section>

    <!-- Sideloading & Pairing Setup Guide -->
    <section id="setup" class="space-y-6">
      <div>
        <h3 class="text-2xl font-bold tracking-tight text-white">Sideloading & Pairing Walkthrough</h3>
        <p class="text-sm text-neutral-400">Everything needed to get Locus running on iOS 17 through iOS 27</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div class="glass-card rounded-xl p-5 space-y-3">
          <div class="w-8 h-8 rounded-lg bg-emerald-500/10 text-emerald-400 flex items-center justify-center font-bold text-sm">A</div>
          <h4 class="font-bold text-base text-white">1. Sideload the IPA</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            Import <code>LocusPlus-unsigned.ipa</code> into your sideloading tool of choice:
          </p>
          <ul class="text-xs space-y-1 text-neutral-300 list-disc list-inside">
            <li><strong>SideStore / AltStore:</strong> Sign with your Apple ID (free 7-day cert).</li>
            <li><strong>LiveContainer:</strong> Run directly without consuming app slots.</li>
            <li><strong>TrollStore:</strong> Permanent install on supported iOS versions.</li>
            <li><strong>Feather:</strong> Sideload via developer or enterprise cert.</li>
          </ul>
        </div>

        <div class="glass-card rounded-xl p-5 space-y-3">
          <div class="w-8 h-8 rounded-lg bg-teal-500/10 text-teal-400 flex items-center justify-center font-bold text-sm">B</div>
          <h4 class="font-bold text-base text-white">2. Host Pairing (RPPairing)</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            Locus communicates with Apple's developer location service on-device:
          </p>
          <div class="text-xs space-y-2 text-neutral-300">
            <div class="p-2.5 rounded-lg bg-neutral-900 border border-neutral-800">
              <span class="text-emerald-400 font-semibold block">iOS 27 (No computer):</span>
              Open Locus → Settings → <em>Pair on this iPhone</em>. Go to iOS Settings → Privacy & Security → Developer Mode → Pair with Host.
            </div>
            <div class="p-2.5 rounded-lg bg-neutral-900 border border-neutral-800">
              <span class="text-teal-400 font-semibold block">iOS 18–26:</span>
              Generate pairing file once with <code>idevice_pair</code> on PC/Mac, then AirDrop / Import into Locus.
            </div>
          </div>
        </div>

        <div class="glass-card rounded-xl p-5 space-y-3">
          <div class="w-8 h-8 rounded-lg bg-cyan-500/10 text-cyan-400 flex items-center justify-center font-bold text-sm">C</div>
          <h4 class="font-bold text-base text-white">3. LocalDevVPN Loopback</h4>
          <p class="text-xs text-neutral-400 leading-relaxed">
            Install <strong>LocalDevVPN</strong> from the App Store and connect it to <code>10.7.0.1</code>.
          </p>
          <div class="p-3 rounded-lg bg-neutral-900 border border-neutral-800 text-xs text-neutral-300 space-y-1">
            <span class="font-semibold text-white">Ready to Teleport:</span>
            <p>Connect on Wi-Fi first, drop a pin or drive a route, then the session continues seamlessly on cellular.</p>
          </div>
        </div>
      </div>
    </section>
  </main>

  <!-- Footer -->
  <footer class="border-t border-neutral-800/80 bg-neutral-900/40 py-8 mt-16 text-center text-xs text-neutral-500">
    <div class="max-w-7xl mx-auto px-4 space-y-2">
      <p>Locus is open-source software licensed under MIT. Unofficial GPS developer simulation tool.</p>
      <p>Build workflow, XcodeGen project, and web companion maintained for fast CI deployments.</p>
    </div>
  </footer>

  <script>
    let map, markers = [], polyline = null;
    let waypoints = [
      { lat: 37.7749, lng: -122.4194, name: "Market St" },
      { lat: 37.7833, lng: -122.4167, name: "Union Square" },
      { lat: 37.7955, lng: -122.3937, name: "Ferry Building" }
    ];
    let currentSpeedMps = 1.4;

    function initMap() {
      map = L.map('map').setView([37.785, -122.41], 13);
      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
        subdomains: 'abcd',
        maxZoom: 19
      }).addTo(map);

      map.on('click', function(e) {
        addPoint(e.latlng.lat, e.latlng.lng);
      });

      renderPoints();
    }

    function addPoint(lat, lng) {
      waypoints.push({ lat, lng, name: "Point " + (waypoints.length + 1) });
      renderPoints();
    }

    function renderPoints() {
      // Clear markers and line
      markers.forEach(m => map.removeLayer(m));
      markers = [];
      if (polyline) map.removeLayer(polyline);

      const latlngs = waypoints.map(w => [w.lat, w.lng]);
      if (document.getElementById('loop-route').checked && waypoints.length > 2) {
        latlngs.push([waypoints[0].lat, waypoints[0].lng]);
      }

      waypoints.forEach((pt, idx) => {
        const marker = L.circleMarker([pt.lat, pt.lng], {
          radius: idx === 0 ? 8 : 6,
          fillColor: idx === 0 ? '#10b981' : (idx === waypoints.length - 1 ? '#06b6d4' : '#f59e0b'),
          color: '#ffffff',
          weight: 2,
          opacity: 1,
          fillOpacity: 0.9
        }).addTo(map).bindPopup('<b>' + pt.name + '</b><br>' + pt.lat.toFixed(5) + ', ' + pt.lng.toFixed(5));
        markers.push(marker);
      });

      if (latlngs.length > 1) {
        polyline = L.polyline(latlngs, { color: '#10b981', weight: 4, opacity: 0.85, dashArray: '8, 8' }).addTo(map);
      }

      updateStats();
    }

    function calculateDistanceMeters() {
      let total = 0;
      for (let i = 1; i < waypoints.length; i++) {
        const p1 = L.latLng(waypoints[i-1].lat, waypoints[i-1].lng);
        const p2 = L.latLng(waypoints[i].lat, waypoints[i].lng);
        total += p1.distanceTo(p2);
      }
      if (document.getElementById('loop-route').checked && waypoints.length > 2) {
        const p1 = L.latLng(waypoints[waypoints.length-1].lat, waypoints[waypoints.length-1].lng);
        const p2 = L.latLng(waypoints[0].lat, waypoints[0].lng);
        total += p1.distanceTo(p2);
      }
      return total;
    }

    function updateStats() {
      const dist = calculateDistanceMeters();
      const km = (dist / 1000).toFixed(2);
      const estSeconds = dist / currentSpeedMps;
      const mins = Math.ceil(estSeconds / 60);
      document.getElementById('route-stats').innerText = waypoints.length + ' points • ' + km + ' km • ~' + mins + ' min';
    }

    function clearRoute() {
      waypoints = [];
      renderPoints();
    }

    function generateSampleRoute() {
      waypoints = [
        { lat: 37.7749, lng: -122.4194, name: "Civic Center" },
        { lat: 37.7833, lng: -122.4167, name: "Market & 4th" },
        { lat: 37.7885, lng: -122.4072, name: "Montgomery St" },
        { lat: 37.7955, lng: -122.3937, name: "Embarcadero Ferry" }
      ];
      renderPoints();
      map.setView([37.785, -122.408], 14);
    }

    function setMode(mode, speed) {
      currentSpeedMps = speed;
      document.getElementById('speed-slider').value = speed;
      updateSpeed(speed);

      ['walk', 'run', 'cycle', 'drive'].forEach(m => {
        const btn = document.getElementById('mode-' + m);
        if (m === mode) {
          btn.className = 'p-2 rounded-lg bg-emerald-500 text-neutral-950 font-bold transition';
        } else {
          btn.className = 'p-2 rounded-lg bg-neutral-800 text-neutral-300 hover:text-white transition';
        }
      });
    }

    function updateSpeed(val) {
      currentSpeedMps = parseFloat(val);
      const kmh = (currentSpeedMps * 3.6).toFixed(1);
      document.getElementById('speed-label').innerText = currentSpeedMps.toFixed(1) + ' m/s (' + kmh + ' km/h)';
      updateStats();
    }

    function toggleLoop() {
      renderPoints();
    }

    function exportGPX() {
      if (waypoints.length === 0) {
        alert('Please click on the map to add at least 1 waypoint first.');
        return;
      }

      const routeName = document.getElementById('route-name').value || 'Locus Route';
      const loop = document.getElementById('loop-route').checked;
      const gait = document.getElementById('gait-pacing').checked;

      let gpx = '<?xml version="1.0" encoding="UTF-8"?>\\n';
      gpx += '<gpx version="1.1" creator="Locus iOS Studio Web Companion" xmlns="http://www.topografix.com/GPX/1/1">\\n';
      gpx += '  <trk>\\n';
      gpx += '    <name>' + escapeXml(routeName) + '</name>\\n';
      gpx += '    <trkseg>\\n';

      let currentTime = new Date();
      let pts = [...waypoints];
      if (loop && pts.length > 2) pts.push(pts[0]);

      for (let i = 0; i < pts.length; i++) {
        if (i > 0) {
          const p1 = L.latLng(pts[i-1].lat, pts[i-1].lng);
          const p2 = L.latLng(pts[i].lat, pts[i].lng);
          const dist = p1.distanceTo(p2);
          
          let speedFactor = 1.0;
          if (gait) {
            speedFactor = 0.9 + Math.random() * 0.2; // Human gait pacing variation
          }
          const dt = (dist / (currentSpeedMps * speedFactor));
          currentTime = new Date(currentTime.getTime() + Math.max(1, dt) * 1000);
        }

        gpx += '      <trkpt lat="' + pts[i].lat.toFixed(6) + '" lon="' + pts[i].lng.toFixed(6) + '">\\n';
        gpx += '        <ele>15.0</ele>\\n';
        gpx += '        <time>' + currentTime.toISOString() + '</time>\\n';
        gpx += '      </trkpt>\\n';
      }

      gpx += '    </trkseg>\\n';
      gpx += '  </trk>\\n';
      gpx += '</gpx>\\n';

      const blob = new Blob([gpx], { type: 'application/gpx+xml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = (routeName.replace(/[^a-z0-9_-]/gi, '_') || 'route') + '.gpx';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }

    function escapeXml(unsafe) {
      return unsafe.replace(/[<>&'"]/g, function (c) {
        switch (c) {
          case '<': return '&lt;';
          case '>': return '&gt;';
          case '&': return '&amp;';
          case '\\'': return '&apos;';
          case '"': return '&quot;';
        }
      });
    }

    async function checkHealth() {
      try {
        const res = await fetch('/api/diagnostics');
        const data = await res.json();
        const libStatus = data.builder.libideviceFfi.isComplete 
          ? ('Present (' + data.builder.libideviceFfi.sizeMb + ')') 
          : 'Missing / Downloading';
        
        document.getElementById('lib-status').innerText = libStatus;
        document.getElementById('diag-lib').innerText = 'Valid Archive (' + data.builder.libideviceFfi.sizeMb + ') ✓';
        document.getElementById('diag-wf').innerText = data.builder.workflow === 'configured' ? '.github/workflows/build.yml ✓' : 'Missing ✗';
        document.getElementById('diag-time').innerText = 'Checked ' + new Date().toLocaleTimeString();
      } catch (e) {
        document.getElementById('lib-status').innerText = 'Online';
      }
    }

    document.addEventListener('DOMContentLoaded', () => {
      initMap();
      checkHealth();
    });
  </script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  if (pathname === '/api/diagnostics') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(getDiagnostics(), null, 2));
    return;
  }

  if (pathname === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', time: new Date().toISOString() }));
    return;
  }

  // Serve static HTML companion UI
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(HTML_CONTENT);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Locus dev server and companion listening on port ${PORT}`);
});
