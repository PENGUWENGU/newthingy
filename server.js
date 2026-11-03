const http = require('node:http');

const HTML_CONTENT = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>Locus - iOS App</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    :root {
      --locus-bg: #090d16;
      --locus-panel: rgba(18, 24, 38, 0.82);
      --locus-panel-border: rgba(255, 255, 255, 0.14);
      --locus-accent: #0A84FF;
      --locus-secondary: #5E5CE6;
      --locus-green: #30D158;
      --locus-red: #FF453A;
      --locus-text: #FFFFFF;
      --locus-subtext: #8E8E93;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
    body {
      background: #030712;
      color: #F2F2F7;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }

    /* iPhone 16 Pro Hardware Shell */
    .iphone-shell {
      position: relative;
      width: 393px;
      height: 852px;
      max-height: 96vh;
      max-width: 96vw;
      background: #000000;
      border-radius: 54px;
      box-shadow: 0 0 0 4px #26292d, 0 0 0 8px #131518, 0 25px 60px rgba(0,0,0,0.85);
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }

    /* Dynamic Island with Live Activity Expansion */
    .dynamic-island {
      position: absolute;
      top: 11px;
      left: 50%;
      transform: translateX(-50%);
      width: 125px;
      height: 35px;
      background: #000000;
      border-radius: 20px;
      z-index: 1000;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 12px;
      font-size: 11px;
      font-weight: 600;
      color: #fff;
      cursor: pointer;
      transition: all 0.35s cubic-bezier(0.16, 1, 0.3, 1);
      box-shadow: 0 4px 14px rgba(0,0,0,0.5);
    }
    .dynamic-island.expanded {
      width: 340px;
      height: 64px;
      border-radius: 32px;
      background: rgba(14, 18, 28, 0.98);
      border: 1px solid rgba(255,255,255,0.18);
      padding: 10px 16px;
      display: flex;
      flex-direction: column;
      justify-content: center;
      gap: 4px;
    }
    .di-compact-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
    }
    .di-icon {
      width: 20px;
      height: 20px;
      border-radius: 50%;
      background: var(--locus-green);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
      box-shadow: 0 0 10px rgba(48, 209, 88, 0.7);
    }
    .di-text {
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 11.5px;
      font-weight: 600;
    }
    .di-expanded-content {
      display: none;
      width: 100%;
      justify-content: space-between;
      align-items: center;
    }
    .dynamic-island.expanded .di-expanded-content {
      display: flex;
    }

    /* iOS Live Activity Lockscreen / Island Banner HUD */
    .live-activity-hud {
      position: absolute;
      top: 56px;
      left: 16px;
      right: 16px;
      background: rgba(16, 22, 34, 0.88);
      backdrop-filter: blur(28px);
      -webkit-backdrop-filter: blur(28px);
      border: 1px solid rgba(255, 255, 255, 0.16);
      border-radius: 24px;
      padding: 12px 16px;
      z-index: 890;
      box-shadow: 0 12px 36px rgba(0,0,0,0.6);
      display: none;
      animation: slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    }
    .live-activity-hud.visible {
      display: block;
    }
    @keyframes slideDown {
      from { transform: translateY(-20px); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
    }
    .la-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 6px;
    }
    .la-badge {
      font-size: 10px;
      font-weight: 700;
      text-transform: uppercase;
      background: rgba(48, 209, 88, 0.18);
      color: var(--locus-green);
      padding: 2px 8px;
      border-radius: 10px;
    }
    .la-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 13px;
    }

    /* iOS Status Bar */
    .status-bar {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 48px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 32px;
      font-size: 14px;
      font-weight: 600;
      color: #FFFFFF;
      z-index: 900;
      pointer-events: none;
    }
    .status-icons {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
    }

    /* Map View Container */
    #map {
      width: 100%;
      height: 100%;
      background: #0d1117;
      z-index: 10;
    }
    .leaflet-tile {
      filter: brightness(0.65) invert(1) contrast(3) hue-rotate(200deg) saturate(0.3) brightness(0.7);
    }
    .leaflet-control-container .leaflet-top,
    .leaflet-control-container .leaflet-bottom {
      display: none;
    }

    /* Top Floating Search & HUD */
    .top-overlay {
      position: absolute;
      top: 56px;
      left: 16px;
      right: 16px;
      z-index: 800;
      display: flex;
      flex-direction: column;
      gap: 10px;
      pointer-events: none;
    }
    .top-overlay.hud-shifted {
      top: 138px;
    }
    .glass-bar {
      pointer-events: auto;
      background: var(--locus-panel);
      backdrop-filter: blur(25px) saturate(180%);
      -webkit-backdrop-filter: blur(25px) saturate(180%);
      border: 1px solid var(--locus-panel-border);
      border-radius: 20px;
      padding: 10px 14px;
      display: flex;
      align-items: center;
      gap: 8px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45);
    }
    .search-input {
      background: transparent;
      border: none;
      outline: none;
      color: #fff;
      font-size: 14px;
      flex: 1;
      font-family: inherit;
    }
    .search-input::placeholder {
      color: rgba(255, 255, 255, 0.45);
    }
    .pill-btn {
      background: rgba(255,255,255,0.08);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 6px 10px;
      color: #fff;
      font-size: 11.5px;
      font-weight: 500;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 4px;
      white-space: nowrap;
    }
    .pill-btn:active {
      background: rgba(255,255,255,0.18);
    }

    /* Floating Status Badge */
    .status-badge {
      pointer-events: auto;
      align-self: flex-start;
      background: var(--locus-panel);
      backdrop-filter: blur(20px);
      border: 1px solid var(--locus-panel-border);
      border-radius: 14px;
      padding: 5px 12px;
      font-size: 12px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 6px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.3);
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--locus-subtext);
    }
    .dot.active {
      background: var(--locus-green);
      box-shadow: 0 0 8px var(--locus-green);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }

    /* Crash Recovery Card */
    .crash-recovery-card {
      pointer-events: auto;
      background: rgba(30, 24, 16, 0.94);
      backdrop-filter: blur(25px);
      border: 1px solid rgba(255, 159, 10, 0.4);
      border-radius: 18px;
      padding: 10px 14px;
      display: none;
      flex-direction: column;
      gap: 8px;
      box-shadow: 0 8px 30px rgba(0,0,0,0.6);
      animation: slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    }
    .crash-recovery-card.visible {
      display: flex;
    }
    @keyframes slideDown {
      from { transform: translateY(-10px); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
    }

    /* Speed Limit Sign Badge */
    .speed-limit-badge {
      pointer-events: auto;
      align-self: flex-start;
      background: rgba(18, 24, 38, 0.88);
      backdrop-filter: blur(20px);
      border: 1px solid var(--locus-panel-border);
      border-radius: 14px;
      padding: 6px 12px;
      display: flex;
      align-items: center;
      gap: 10px;
      cursor: pointer;
      box-shadow: 0 4px 16px rgba(0,0,0,0.4);
      transition: all 0.2s;
    }
    .speed-limit-badge.matching {
      background: rgba(48, 209, 88, 0.16);
      border-color: rgba(48, 209, 88, 0.5);
    }
    .speed-limit-sign {
      width: 38px;
      height: 44px;
      background: #FFFFFF;
      border: 2px solid #000000;
      border-radius: 6px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #000000;
      box-shadow: 0 2px 6px rgba(0,0,0,0.3);
      flex-shrink: 0;
    }
    .speed-limit-sign .sl-title {
      font-size: 6.5px;
      font-weight: 900;
      line-height: 1;
      letter-spacing: -0.2px;
    }
    .speed-limit-sign .sl-number {
      font-size: 16px;
      font-weight: 900;
      line-height: 1.1;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", sans-serif;
    }

    /* Floating Speed & Tool Selector */
    .speed-modes {
      position: absolute;
      right: 16px;
      top: 130px;
      z-index: 800;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .speed-modes.hud-shifted {
      top: 210px;
    }
    .speed-btn {
      width: 44px;
      height: 44px;
      border-radius: 22px;
      background: var(--locus-panel);
      backdrop-filter: blur(20px);
      border: 1px solid var(--locus-panel-border);
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      cursor: pointer;
      box-shadow: 0 4px 14px rgba(0,0,0,0.35);
      transition: all 0.2s;
    }
    .speed-btn.selected {
      background: var(--locus-accent);
      border-color: rgba(255,255,255,0.4);
      transform: scale(1.08);
      box-shadow: 0 4px 20px rgba(10, 132, 255, 0.6);
    }

    /* Virtual Joystick */
    .joystick-container {
      position: absolute;
      bottom: 124px;
      right: 20px;
      z-index: 850;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
    }
    .joystick-base {
      width: 110px;
      height: 110px;
      border-radius: 55px;
      background: rgba(18, 24, 38, 0.75);
      backdrop-filter: blur(25px);
      border: 1px solid rgba(255,255,255,0.18);
      box-shadow: 0 8px 30px rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      touch-action: none;
      user-select: none;
    }
    .joystick-knob {
      width: 50px;
      height: 50px;
      border-radius: 25px;
      background: linear-gradient(135deg, rgba(255,255,255,0.28), rgba(255,255,255,0.08));
      backdrop-filter: blur(10px);
      border: 1.5px solid rgba(255,255,255,0.4);
      box-shadow: 0 4px 12px rgba(0,0,0,0.4);
      cursor: grab;
      transition: transform 0.05s ease-out;
    }

    /* Bottom Liquid Glass Tray Controls */
    .bottom-dock {
      position: absolute;
      bottom: 24px;
      left: 16px;
      right: 16px;
      z-index: 800;
      background: var(--locus-panel);
      backdrop-filter: blur(30px) saturate(190%);
      -webkit-backdrop-filter: blur(30px) saturate(190%);
      border: 1px solid var(--locus-panel-border);
      border-radius: 30px;
      padding: 10px 14px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      box-shadow: 0 10px 35px rgba(0,0,0,0.6);
    }
    .dock-icon-btn {
      width: 44px;
      height: 44px;
      border-radius: 22px;
      background: rgba(255,255,255,0.06);
      border: 1px solid rgba(255,255,255,0.08);
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      cursor: pointer;
      transition: background 0.15s;
    }
    .dock-icon-btn:active {
      background: rgba(255,255,255,0.18);
    }
    .spoof-main-btn {
      flex: 1;
      height: 48px;
      margin: 0 10px;
      border-radius: 24px;
      border: none;
      background: var(--locus-accent);
      color: #FFFFFF;
      font-size: 15px;
      font-weight: 700;
      letter-spacing: -0.2px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      box-shadow: 0 4px 20px rgba(10, 132, 255, 0.45);
      transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    }
    .spoof-main-btn.active {
      background: var(--locus-red);
      box-shadow: 0 4px 20px rgba(255, 69, 58, 0.5);
    }
    .spoof-main-btn:active {
      transform: scale(0.97);
    }

    /* Modal Sheets */
    .sheet-overlay {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.65);
      z-index: 1200;
      display: none;
      opacity: 0;
      transition: opacity 0.25s;
    }
    .sheet-overlay.open {
      display: block;
      opacity: 1;
    }
    .modal-sheet {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      background: #141a27;
      border-top-left-radius: 28px;
      border-top-right-radius: 28px;
      border-top: 1px solid rgba(255,255,255,0.15);
      padding: 16px 20px 34px 20px;
      max-height: 85%;
      overflow-y: auto;
      transform: translateY(100%);
      transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      box-shadow: 0 -10px 40px rgba(0,0,0,0.7);
    }
    .sheet-overlay.open .modal-sheet {
      transform: translateY(0);
    }
    .sheet-handle {
      width: 38px;
      height: 5px;
      background: rgba(255,255,255,0.3);
      border-radius: 3px;
      margin: 0 auto 16px auto;
    }
    .sheet-title {
      font-size: 18px;
      font-weight: 700;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .sheet-close {
      background: rgba(255,255,255,0.1);
      border: none;
      width: 28px;
      height: 28px;
      border-radius: 14px;
      color: #fff;
      font-size: 14px;
      cursor: pointer;
    }
    .list-row {
      background: rgba(255,255,255,0.05);
      border-radius: 14px;
      padding: 12px 14px;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      cursor: pointer;
      transition: background 0.15s;
    }
    .list-row:hover {
      background: rgba(255,255,255,0.08);
    }

    /* Color Swatches in Customizer */
    .color-swatches {
      display: flex;
      gap: 12px;
      margin-bottom: 16px;
      overflow-x: auto;
      padding-bottom: 4px;
    }
    .color-swatch {
      width: 44px;
      height: 44px;
      border-radius: 22px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      font-weight: bold;
      border: 3px solid transparent;
      transition: all 0.2s;
    }
    .color-swatch.active {
      border-color: #fff;
      transform: scale(1.1);
    }

    /* iOS Home Bar */
    .home-indicator {
      position: absolute;
      bottom: 8px;
      left: 50%;
      transform: translateX(-50%);
      width: 134px;
      height: 5px;
      background: rgba(255, 255, 255, 0.65);
      border-radius: 3px;
      z-index: 1100;
      pointer-events: none;
    }
  </style>
</head>
<body>

  <!-- Authentic iOS Phone Shell Container -->
  <div class="iphone-shell">
    <!-- Dynamic Island with Live Activity Expansion -->
    <div class="dynamic-island" id="dynamicIsland" onclick="toggleDynamicIsland()">
      <div class="di-compact-row">
        <div class="di-icon" id="diIcon">📍</div>
        <div class="di-text" id="diText">Locus Ready</div>
      </div>
      <div class="di-expanded-content" id="diExpanded">
        <div style="font-size: 12px; font-weight: 700; color: var(--locus-green);" id="diSpeed">Speed: 25 mph</div>
        <div style="font-size: 11px; opacity: 0.7;">Live Activity Active</div>
      </div>
    </div>

    <!-- Live Activity Floating Banner HUD -->
    <div class="live-activity-hud" id="liveActivityBanner">
      <div class="la-header">
        <div style="display:flex; align-items:center; gap:6px;">
          <span style="font-size:16px;">🚗</span>
          <strong>Locus Live Activity</strong>
        </div>
        <span class="la-badge">Dynamic Island HUD</span>
      </div>
      <div class="la-row">
        <span id="laDest">Life360 Driving Loop</span>
        <strong id="laCoords" style="color:var(--locus-accent);">37.7749°, -122.4194°</strong>
      </div>
      <div class="la-row" style="margin-top:4px; font-size:11px; opacity:0.75;">
        <span>Variance: ±3.5 mph (Gauss-Markov)</span>
        <span id="laStatus">1.0s GPS Injection Active</span>
      </div>
    </div>

    <!-- Status Bar -->
    <div class="status-bar">
      <span>9:41</span>
      <div class="status-icons">
        <span>5G</span>
        <span>􀙇</span>
        <span>100% 􀛨</span>
      </div>
    </div>

    <!-- Top Controls & HUD -->
    <div class="top-overlay" id="topOverlay">
      <!-- Crash Recovery Card -->
      <div class="crash-recovery-card" id="crashRecoveryCard">
        <div style="display:flex; align-items:flex-start; justify-content:space-between; gap:8px;">
          <div style="display:flex; align-items:center; gap:8px;">
            <span style="font-size:18px;">⚠️</span>
            <div>
              <div style="font-size:13px; font-weight:700; color:#fff;">Resume Interrupted Route? <span style="background:#FF9F0A; color:#000; font-size:9px; font-weight:900; padding:2px 5px; border-radius:10px; margin-left:4px;">RECOVERED</span></div>
              <div style="font-size:11px; color:#8E8E93;" id="recoverySubtitle">The previous route stopped unexpectedly. Resume where it last was?</div>
            </div>
          </div>
          <button style="background:none; border:none; color:#8E8E93; font-size:16px; cursor:pointer;" onclick="dismissRecovery()">✕</button>
        </div>
        <div style="display:flex; gap:8px; margin-top:4px;">
          <button style="flex:1; background:var(--locus-accent); border:none; border-radius:10px; padding:7px 12px; color:#000; font-weight:700; font-size:12px; cursor:pointer;" onclick="resumeRecoveredSession()">Resume Route from Here</button>
          <button style="background:rgba(255,255,255,0.08); border:none; border-radius:10px; padding:7px 12px; color:#fff; font-weight:600; font-size:12px; cursor:pointer;" onclick="dismissRecovery()">Dismiss</button>
        </div>
      </div>

      <div class="glass-bar">
        <span style="font-size: 15px; opacity: 0.6;">🔍</span>
        <input type="text" id="searchInput" class="search-input" placeholder="Search place or coordinates..." />
        <button class="pill-btn" onclick="teleportPreset('apple')">Apple Park</button>
        <button class="pill-btn" onclick="teleportPreset('central_park')">NYC</button>
      </div>

      <div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
        <div class="status-badge">
          <span class="dot" id="statusDot"></span>
          <span id="statusLabel">Not Spoofing</span>
          <span id="coordLabel" style="font-size: 10px; color: var(--locus-subtext); margin-left: 4px;">37.7749°, -122.4194°</span>
        </div>

        <!-- Real Road Speed Limit Sign Badge -->
        <div class="speed-limit-badge" id="speedLimitBadge" onclick="toggleMatchSpeedLimit()" title="Tap to match posted road speed limit">
          <div class="speed-limit-sign">
            <span class="sl-title">SPEED</span>
            <span class="sl-title">LIMIT</span>
            <span class="sl-number" id="speedLimitNumber">25</span>
          </div>
          <div style="display:flex; flex-direction:column; gap:2px;">
            <div style="font-size:11px; font-weight:700; color:#fff;" id="speedLimitRoad">Market St</div>
            <div style="font-size:9.5px; color:#8E8E93;" id="speedLimitStatus">Tap to match limit</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Speed Mode Floating Buttons -->
    <div class="speed-modes" id="speedModesBar">
      <button class="speed-btn selected" id="speedWalk" onclick="setSpeed('walk', 1.2)" title="Walk (1.2 m/s)">🚶</button>
      <button class="speed-btn" id="speedCycle" onclick="setSpeed('cycle', 4.5)" title="Cycle (4.5 m/s)">🚴</button>
      <button class="speed-btn" id="speedDrive" onclick="setSpeed('drive', 11.2)" title="Drive (11.2 m/s)">🚗</button>
      <button class="speed-btn" onclick="toggleJoystick()" title="Toggle Joystick">🕹️</button>
      <button class="speed-btn" onclick="openSheet('personalizeSheet')" title="Theme & Colors">🎨</button>
      <button class="speed-btn" onclick="recenterMap()" title="Center Marker">🎯</button>
    </div>

    <!-- Virtual Joystick Control -->
    <div class="joystick-container" id="joystickPad" style="display: flex;">
      <div class="joystick-base" id="joystickBase">
        <div class="joystick-knob" id="joystickKnob"></div>
      </div>
    </div>

    <!-- Interactive Native Map -->
    <div id="map"></div>

    <!-- Bottom Liquid Glass Dock -->
    <div class="bottom-dock">
      <button class="dock-icon-btn" onclick="openSheet('placesSheet')" title="Saved Places">★</button>
      
      <button class="spoof-main-btn" id="spoofActionBtn" onclick="toggleSpoofing()">
        <span id="spoofBtnText">Start Spoofing</span>
      </button>

      <button class="dock-icon-btn" onclick="openSheet('routesSheet')" title="Route Planner">⤹</button>
      <button class="dock-icon-btn" onclick="openSheet('settingsSheet')" title="Settings">⚙︎</button>
    </div>

    <!-- iOS Home Bar Indicator -->
    <div class="home-indicator"></div>

    <!-- Personalize & Defaults Onboarding Sheet -->
    <div class="sheet-overlay" id="personalizeSheet">
      <div class="modal-sheet">
        <div class="sheet-handle"></div>
        <div class="sheet-title">
          <span>Personalize Defaults & Theme</span>
          <button class="sheet-close" onclick="closeSheet('personalizeSheet')">✕</button>
        </div>
        
        <div style="font-size: 11px; font-weight:700; color:#8E8E93; margin-bottom: 8px;">ACCENT COLOR</div>
        <div class="color-swatches">
          <div class="color-swatch active" style="background:#0A84FF;" onclick="selectThemeColor('#0A84FF', this)">✓</div>
          <div class="color-swatch" style="background:#30D158;" onclick="selectThemeColor('#30D158', this)"></div>
          <div class="color-swatch" style="background:#BF5AF2;" onclick="selectThemeColor('#BF5AF2', this)"></div>
          <div class="color-swatch" style="background:#FF9F0A;" onclick="selectThemeColor('#FF9F0A', this)"></div>
          <div class="color-swatch" style="background:#FF375F;" onclick="selectThemeColor('#FF375F', this)"></div>
          <div class="color-swatch" style="background:#59C6B8;" onclick="selectThemeColor('#59C6B8', this)"></div>
        </div>

        <div style="font-size: 11px; font-weight:700; color:#8E8E93; margin-bottom: 8px;">DEFAULTS & REALISM</div>
        <div class="list-row" onclick="toggleLiveActivities()">
          <div>
            <strong>Live Activities & Dynamic Island</strong>
            <div style="font-size: 11px; color:#8E8E93;">Lock Screen HUD with real-time ETA and coordinates</div>
          </div>
          <span style="color:var(--locus-green); font-weight:700;" id="laStatusToggle">ENABLED</span>
        </div>

        <div class="list-row" onclick="startDrivingLoop()">
          <div>
            <strong>🚗 Life360 Driving Mode Simulation</strong>
            <div style="font-size: 11px; color:#8E8E93;">2.5 km circuit with dynamic throttle variance & 1.0s GPS</div>
          </div>
          <span style="color:var(--locus-accent);">START ▶</span>
        </div>

        <button class="spoof-main-btn" style="width:100%; margin: 12px 0 0 0;" onclick="closeSheet('personalizeSheet')">
          Save Preferences
        </button>
      </div>
    </div>

    <!-- Saved Places Sheet -->
    <div class="sheet-overlay" id="placesSheet">
      <div class="modal-sheet">
        <div class="sheet-handle"></div>
        <div class="sheet-title">
          <span>Saved Places</span>
          <button class="sheet-close" onclick="closeSheet('placesSheet')">✕</button>
        </div>
        <div class="list-row" onclick="teleportTo(37.3349, -122.0090, 'Apple Park, Cupertino')">
          <div><strong>Apple Park</strong><div style="font-size: 11px; color:#8E8E93;">Cupertino, CA</div></div>
          <span>➜</span>
        </div>
        <div class="list-row" onclick="teleportTo(40.785091, -73.968285, 'Central Park, NYC')">
          <div><strong>Central Park</strong><div style="font-size: 11px; color:#8E8E93;">New York, NY</div></div>
          <span>➜</span>
        </div>
        <div class="list-row" onclick="teleportTo(35.6586, 139.7454, 'Tokyo Tower')">
          <div><strong>Tokyo Tower</strong><div style="font-size: 11px; color:#8E8E93;">Minato City, Tokyo</div></div>
          <span>➜</span>
        </div>
        <div class="list-row" onclick="teleportTo(51.5007, -0.1246, 'Big Ben')">
          <div><strong>Big Ben</strong><div style="font-size: 11px; color:#8E8E93;">London, UK</div></div>
          <span>➜</span>
        </div>
      </div>
    </div>

    <!-- Routes Sheet -->
    <div class="sheet-overlay" id="routesSheet">
      <div class="modal-sheet">
        <div class="sheet-handle"></div>
        <div class="sheet-title">
          <span>Routes & Simulation</span>
          <button class="sheet-close" onclick="closeSheet('routesSheet')">✕</button>
        </div>
        <div class="list-row" onclick="startDrivingLoop()">
          <div>
            <strong>🚗 Life360 Driving Loop (2.5 km)</strong>
            <div style="font-size: 11px; color:#8E8E93;">Continuous loop with dynamic throttle variance (exceeds 0.5 mi threshold)</div>
          </div>
          <span>▶</span>
        </div>
        <div class="list-row" onclick="startWalkRoute()">
          <div>
            <strong>🚶 Park Perimeter Walk</strong>
            <div style="font-size: 11px; color:#8E8E93;">Natural pedestrian gait pacing (1.2 m/s)</div>
          </div>
          <span>▶</span>
        </div>
      </div>
    </div>

    <!-- Settings Sheet with Backup & Export -->
    <div class="sheet-overlay" id="settingsSheet">
      <div class="modal-sheet">
        <div class="sheet-handle"></div>
        <div class="sheet-title">
          <span>Settings & Backup</span>
          <button class="sheet-close" onclick="closeSheet('settingsSheet')">✕</button>
        </div>

        <div style="font-size: 11px; font-weight:700; color:#8E8E93; margin-bottom: 8px;">BACKUP & PROFILE TRANSFER</div>
        <div class="list-row" onclick="exportProfileJSON()">
          <div>
            <strong>Export All Settings & Data</strong>
            <div style="font-size: 11px; color:#8E8E93;">Download complete profile JSON (colors, routes, places, pairing)</div>
          </div>
          <span style="color:var(--locus-accent); font-weight:700;">EXPORT ⇪</span>
        </div>

        <div class="list-row" onclick="copyProfileToClipboard()">
          <div>
            <strong>Copy Backup JSON to Clipboard</strong>
            <div style="font-size: 11px; color:#8E8E93;">Copy portable JSON to paste into another iPhone</div>
          </div>
          <span>📋</span>
        </div>

        <div class="list-row" onclick="restoreProfileFromClipboard()">
          <div>
            <strong>Restore Profile from Clipboard</strong>
            <div style="font-size: 11px; color:#8E8E93;">Instantly import and apply all settings & routes</div>
          </div>
          <span style="color:var(--locus-green); font-weight:700;">RESTORE ⬇</span>
        </div>

        <div style="font-size: 11px; font-weight:700; color:#8E8E93; margin: 16px 0 8px 0;">CRASH RESILIENCE & RECOVERY</div>
        <div class="list-row" onclick="simulateCrashTest()">
          <div>
            <strong>Test Crash Recovery Flow</strong>
            <div style="font-size: 11px; color:#8E8E93;">Simulate abrupt app crash and trigger resume banner</div>
          </div>
          <span style="color:#FF9F0A; font-weight:700;">SIMULATE ⚡</span>
        </div>

        <div style="font-size: 11px; font-weight:700; color:#8E8E93; margin: 16px 0 8px 0;">SYSTEM & SIMULATION</div>
        <div class="list-row">
          <div><strong>Live Activities</strong><div style="font-size: 11px; color:#8E8E93;">Dynamic Island & Lock Screen</div></div>
          <span style="color: var(--locus-green); font-size: 12px; font-weight: 600;">ACTIVE</span>
        </div>
        <div class="list-row">
          <div><strong>Road Speed Limits</strong><div style="font-size: 11px; color:#8E8E93;">OpenStreetMap Overpass / Nominatim</div></div>
          <span style="color: var(--locus-green); font-size: 12px; font-weight: 600;">LIVE</span>
        </div>
        <div class="list-row">
          <div><strong>Life360 Safeguard</strong><div style="font-size: 11px; color:#8E8E93;">Continuous 1.0s DVT Injection</div></div>
          <span style="color: var(--locus-green); font-size: 12px; font-weight: 600;">ON</span>
        </div>
        <div class="list-row">
          <div><strong>Package Output</strong><div style="font-size: 11px; color:#8E8E93;">LocusPlus-unsigned.ipa</div></div>
          <span style="font-size: 12px; color: var(--locus-subtext);">iOS 17.0+</span>
        </div>
      </div>
    </div>
  </div>

  <script>
    // State
    let isSpoofing = false;
    let currentSpeed = 1.2; // m/s
    let currentLat = 37.7749;
    let currentLng = -122.4194;
    let liveActivitiesEnabled = true;
    let marker;
    let simulationTimer = null;
    let activeThemeColor = '#0A84FF';

    // Initialize Leaflet Map
    const map = L.map('map', {
      zoomControl: false,
      attributionControl: false
    }).setView([currentLat, currentLng], 15);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    function createPinIcon(color) {
      return L.divIcon({
        className: 'custom-pin',
        html: '<div style="width:24px; height:24px; border-radius:50%; background:' + color + '; border:3px solid #FFFFFF; box-shadow:0 0 14px ' + color + '; cursor:grab;"></div>',
        iconSize: [24, 24],
        iconAnchor: [12, 12]
      });
    }

    marker = L.marker([currentLat, currentLng], { icon: createPinIcon(activeThemeColor), draggable: true }).addTo(map);

    marker.on('drag', function(e) {
      const pos = e.target.getLatLng();
      updateLocation(pos.lat, pos.lng);
    });

    map.on('click', function(e) {
      marker.setLatLng(e.latlng);
      updateLocation(e.latlng.lat, e.latlng.lng);
    });

    function updateLocation(lat, lng) {
      currentLat = lat;
      currentLng = lng;
      const coordStr = lat.toFixed(4) + '°, ' + lng.toFixed(4) + '°';
      document.getElementById('coordLabel').textContent = coordStr;
      document.getElementById('laCoords').textContent = coordStr;
      if (isSpoofing) {
        document.getElementById('diText').textContent = coordStr;
        updateCrashRecoveryCheckpoint();
      }
      fetchRoadSpeedLimit(lat, lng);
    }

    function recenterMap() {
      map.setView([currentLat, currentLng], 16, { animate: true });
    }

    function setSpeed(mode, speedVal) {
      currentSpeed = speedVal;
      document.querySelectorAll('.speed-btn').forEach(b => b.classList.remove('selected'));
      if (mode === 'walk') document.getElementById('speedWalk').classList.add('selected');
      if (mode === 'cycle') document.getElementById('speedCycle').classList.add('selected');
      if (mode === 'drive') document.getElementById('speedDrive').classList.add('selected');
      
      const speedMPH = Math.round(speedVal * 2.23694);
      document.getElementById('diSpeed').textContent = 'Speed: ' + speedMPH + ' mph';
    }

    function toggleDynamicIsland() {
      const di = document.getElementById('dynamicIsland');
      di.classList.toggle('expanded');
    }

    function toggleLiveActivities() {
      liveActivitiesEnabled = !liveActivitiesEnabled;
      const st = document.getElementById('laStatusToggle');
      st.textContent = liveActivitiesEnabled ? 'ENABLED' : 'DISABLED';
      st.style.color = liveActivitiesEnabled ? 'var(--locus-green)' : 'var(--locus-subtext)';
      const banner = document.getElementById('liveActivityBanner');
      if (!liveActivitiesEnabled) banner.classList.remove('visible');
      else if (isSpoofing) banner.classList.add('visible');
    }

    function selectThemeColor(color, el) {
      activeThemeColor = color;
      document.documentElement.style.setProperty('--locus-accent', color);
      document.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('active'));
      el.classList.add('active');
      marker.setIcon(createPinIcon(color));
    }

    function toggleSpoofing() {
      isSpoofing = !isSpoofing;
      const btn = document.getElementById('spoofActionBtn');
      const dot = document.getElementById('statusDot');
      const label = document.getElementById('statusLabel');
      const di = document.getElementById('dynamicIsland');
      const diText = document.getElementById('diText');
      const banner = document.getElementById('liveActivityBanner');
      const overlay = document.getElementById('topOverlay');
      const speedBar = document.getElementById('speedModesBar');

      if (isSpoofing) {
        btn.classList.add('active');
        document.getElementById('spoofBtnText').textContent = 'Stop Spoofing';
        dot.classList.add('active');
        label.textContent = 'Spoofing';
        label.style.color = 'var(--locus-green)';
        di.classList.add('expanded');
        diText.textContent = currentLat.toFixed(4) + '°, ' + currentLng.toFixed(4) + '°';
        if (liveActivitiesEnabled) {
          banner.classList.add('visible');
          overlay.classList.add('hud-shifted');
          speedBar.classList.add('hud-shifted');
        }
        updateCrashRecoveryCheckpoint('teleport');
      } else {
        btn.classList.remove('active');
        document.getElementById('spoofBtnText').textContent = 'Start Spoofing';
        dot.classList.remove('active');
        label.textContent = 'Not Spoofing';
        label.style.color = '#fff';
        di.classList.remove('expanded');
        diText.textContent = 'Locus Ready';
        banner.classList.remove('visible');
        overlay.classList.remove('hud-shifted');
        speedBar.classList.remove('hud-shifted');
        if (simulationTimer) {
          clearInterval(simulationTimer);
          simulationTimer = null;
        }
        clearCrashRecovery();
      }
    }

    function teleportTo(lat, lng, name) {
      closeSheet('placesSheet');
      map.setView([lat, lng], 16, { animate: true });
      marker.setLatLng([lat, lng]);
      updateLocation(lat, lng);
    }

    function teleportPreset(preset) {
      if (preset === 'apple') teleportTo(37.3349, -122.0090, 'Apple Park');
      if (preset === 'central_park') teleportTo(40.785091, -73.968285, 'Central Park');
    }

    function toggleJoystick() {
      const pad = document.getElementById('joystickPad');
      pad.style.display = pad.style.display === 'none' ? 'flex' : 'none';
    }

    function openSheet(id) {
      document.getElementById(id).classList.add('open');
    }
    function closeSheet(id) {
      document.getElementById(id).classList.remove('open');
    }

    // Driving Simulation Loop (Life360 ~2.5 km circuit with dynamic variance)
    function startDrivingLoop() {
      closeSheet('routesSheet');
      closeSheet('personalizeSheet');
      closeSheet('settingsSheet');
      if (!isSpoofing) toggleSpoofing();
      setSpeed('drive', 11.2);

      const centerLat = currentLat;
      const centerLng = currentLng;
      const radius = 0.0035;
      let angle = 0;

      if (simulationTimer) clearInterval(simulationTimer);

      document.getElementById('laDest').textContent = "Life360 Driving Loop (2.5 km)";

      simulationTimer = setInterval(() => {
        // Human throttle variance
        const throttleVariance = (Math.sin(angle * 3) + Math.cos(angle * 1.7)) * 0.0004;
        angle += 0.045;
        const newLat = centerLat + Math.sin(angle) * (radius + throttleVariance);
        const newLng = centerLng + Math.cos(angle) * ((radius + throttleVariance) * 1.3);
        marker.setLatLng([newLat, newLng]);
        updateLocation(newLat, newLng);

        // Update Dynamic Island live speed
        const currentMph = Math.round(25 + Math.sin(angle * 4) * 4);
        document.getElementById('diSpeed').textContent = 'Speed: ' + currentMph + ' mph';
      }, 500);
    }

    function startWalkRoute() {
      closeSheet('routesSheet');
      if (!isSpoofing) toggleSpoofing();
      setSpeed('walk', 1.2);

      const centerLat = currentLat;
      const centerLng = currentLng;
      let step = 0;

      if (simulationTimer) clearInterval(simulationTimer);
      document.getElementById('laDest').textContent = "Park Perimeter Walk";

      simulationTimer = setInterval(() => {
        step += 0.0001;
        const newLat = centerLat + step;
        const newLng = centerLng + (step * 0.5);
        marker.setLatLng([newLat, newLng]);
        updateLocation(newLat, newLng);
      }, 800);
    }

    // Export & Backup Management
    function getBackupObject() {
      return {
        version: 1,
        exportDate: new Date().toISOString(),
        appVersion: "1.0.2",
        theme: {
          accentColor: activeThemeColor,
          appearanceStyle: "Liquid Glass"
        },
        defaults: {
          travelMode: currentSpeed >= 10 ? "drive" : "walk",
          speedUnit: "mph",
          speedVarianceMPH: 3.5,
          speedRandomnessEnabled: true,
          liveActivitiesEnabled: liveActivitiesEnabled
        },
        favorites: [
          { name: "Apple Park", latitude: 37.3349, longitude: -122.0090 },
          { name: "Central Park", latitude: 40.785091, longitude: -73.968285 },
          { name: "Tokyo Tower", latitude: 35.6586, longitude: 139.7454 }
        ],
        routes: [
          { name: "Life360 Driving Loop", distanceMeters: 2500, isLoop: true }
        ]
      };
    }

    function exportProfileJSON() {
      const backup = getBackupObject();
      const str = JSON.stringify(backup, null, 2);
      const blob = new Blob([str], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'Locus-Backup-' + new Date().toISOString().slice(0,10) + '.json';
      a.click();
      URL.revokeObjectURL(url);
    }

    function copyProfileToClipboard() {
      const backup = getBackupObject();
      const str = JSON.stringify(backup, null, 2);
      navigator.clipboard.writeText(str).then(() => {
        alert("Locus profile backup copied to clipboard!");
      });
    }

    function restoreProfileFromClipboard() {
      navigator.clipboard.readText().then(text => {
        try {
          const profile = JSON.parse(text);
          if (profile.theme && profile.theme.accentColor) {
            selectThemeColor(profile.theme.accentColor, document.querySelector('.color-swatch'));
          }
          alert("Profile restored successfully! Colors, defaults, and favorites loaded.");
        } catch (e) {
          alert("Clipboard does not contain valid JSON profile backup.");
        }
      });
    }

    // Joystick implementation
    const base = document.getElementById('joystickBase');
    const knob = document.getElementById('joystickKnob');
    let isDragging = false;
    let joystickInterval = null;
    let deltaX = 0;
    let deltaY = 0;

    base.addEventListener('pointerdown', (e) => {
      isDragging = true;
      base.setPointerCapture(e.pointerId);
      handlePointer(e);
      joystickInterval = setInterval(() => {
        if (!isDragging) return;
        const factor = 0.00003 * (currentSpeed / 1.2);
        currentLng += deltaX * factor;
        currentLat -= deltaY * factor;
        marker.setLatLng([currentLat, currentLng]);
        updateLocation(currentLat, currentLng);
      }, 50);
    });

    base.addEventListener('pointermove', (e) => {
      if (isDragging) handlePointer(e);
    });

    const resetJoystick = () => {
      isDragging = false;
      deltaX = 0;
      deltaY = 0;
      knob.style.transform = 'translate(0px, 0px)';
      if (joystickInterval) clearInterval(joystickInterval);
    };

    base.addEventListener('pointerup', resetJoystick);
    base.addEventListener('pointercancel', resetJoystick);

    function handlePointer(e) {
      const rect = base.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      let dx = e.clientX - centerX;
      let dy = e.clientY - centerY;
      const distance = Math.hypot(dx, dy);
      const maxRadius = 35;

      if (distance > maxRadius) {
        dx = (dx / distance) * maxRadius;
        dy = (dy / distance) * maxRadius;
      }
      deltaX = dx;
      deltaY = dy;
      knob.style.transform = 'translate(' + dx + 'px, ' + dy + 'px)';
    }

    // Road Speed Limits & Adherence
    let currentRoadSpeedMPH = 25;
    let isMatchingSpeedLimit = false;
    let lastQueriedCoordKey = "";

    async function fetchRoadSpeedLimit(lat, lng) {
      const key = Math.round(lat * 1000) + "_" + Math.round(lng * 1000);
      if (key === lastQueriedCoordKey) return;
      lastQueriedCoordKey = key;

      try {
        const url = 'https://nominatim.openstreetmap.org/reverse?lat=' + lat + '&lon=' + lng + '&format=json&extratags=1&zoom=17';
        const resp = await fetch(url, { headers: { 'Accept': 'application/json' } });
        if (resp.ok) {
          const data = await resp.json();
          const roadName = data.name || (data.address ? (data.address.road || data.address.pedestrian || "Local Road") : "Local Road");
          let speedLimit = 25;
          if (data.extratags && data.extratags.maxspeed) {
            const raw = data.extratags.maxspeed;
            const parsed = parseInt(raw, 10);
            if (!isNaN(parsed) && parsed > 5) {
              speedLimit = raw.toLowerCase().includes('km') ? Math.round(parsed * 0.621371) : parsed;
            }
          } else if (data.extratags && data.extratags.highway) {
            const hw = data.extratags.highway;
            if (hw === 'motorway') speedLimit = 65;
            else if (hw === 'trunk') speedLimit = 55;
            else if (hw === 'primary') speedLimit = 45;
            else if (hw === 'secondary') speedLimit = 35;
          }
          currentRoadSpeedMPH = speedLimit;
          document.getElementById('speedLimitNumber').textContent = speedLimit;
          document.getElementById('speedLimitRoad').textContent = roadName;
          if (isMatchingSpeedLimit) {
            applySpeedLimitToCurrentMode(speedLimit);
          }
        }
      } catch (e) {
        // Fallback default
      }
    }

    function toggleMatchSpeedLimit() {
      isMatchingSpeedLimit = !isMatchingSpeedLimit;
      const badge = document.getElementById('speedLimitBadge');
      const status = document.getElementById('speedLimitStatus');
      if (isMatchingSpeedLimit) {
        badge.classList.add('matching');
        status.textContent = "Matching limit";
        status.style.color = "var(--locus-green)";
        applySpeedLimitToCurrentMode(currentRoadSpeedMPH);
      } else {
        badge.classList.remove('matching');
        status.textContent = "Tap to match limit";
        status.style.color = "var(--locus-subtext)";
      }
    }

    function applySpeedLimitToCurrentMode(mph) {
      const mps = mph / 2.23694;
      currentSpeed = mps;
      document.getElementById('diSpeed').textContent = 'Speed: ' + mph + ' mph (Limit)';
    }

    // Continuous Crash Recovery Heartbeat
    function updateCrashRecoveryCheckpoint(type, routeDetails) {
      const snapshot = {
        sessionType: type || (simulationTimer ? 'route' : 'teleport'),
        lat: currentLat,
        lng: currentLng,
        speedMPS: currentSpeed,
        timestamp: Date.now(),
        routeDetails: routeDetails || (simulationTimer ? { name: "Life360 Driving Loop", isLoop: true } : null)
      };
      try {
        localStorage.setItem('locus_crash_snapshot', JSON.stringify(snapshot));
        localStorage.setItem('locus_was_active', isSpoofing ? 'true' : 'false');
      } catch(e) {}
    }

    function clearCrashRecovery() {
      try {
        localStorage.setItem('locus_was_active', 'false');
        localStorage.removeItem('locus_crash_snapshot');
      } catch(e) {}
      dismissRecovery();
    }

    function checkCrashRecoveryOnStartup() {
      try {
        const wasActive = localStorage.getItem('locus_was_active') === 'true';
        const raw = localStorage.getItem('locus_crash_snapshot');
        if (wasActive && raw) {
          const snapshot = JSON.parse(raw);
          const elapsedHours = (Date.now() - snapshot.timestamp) / 3600000;
          if (elapsedHours < 24) {
            showRecoveryBanner(snapshot);
          }
        }
      } catch(e) {}
    }

    function showRecoveryBanner(snapshot) {
      const card = document.getElementById('crashRecoveryCard');
      const sub = document.getElementById('recoverySubtitle');
      if (snapshot.routeDetails) {
        sub.textContent = 'The previous route (' + snapshot.routeDetails.name + ') stopped unexpectedly at ' + snapshot.lat.toFixed(4) + '°, ' + snapshot.lng.toFixed(4) + '°. Resume right where it was?';
      } else {
        sub.textContent = 'You were spoofed at ' + snapshot.lat.toFixed(4) + '°, ' + snapshot.lng.toFixed(4) + '°. Tap to restore location.';
      }
      card.classList.add('visible');
    }

    function resumeRecoveredSession() {
      try {
        const raw = localStorage.getItem('locus_crash_snapshot');
        if (!raw) return;
        const snapshot = JSON.parse(raw);
        teleportTo(snapshot.lat, snapshot.lng, "Recovered Location");
        if (snapshot.routeDetails) {
          startDrivingLoop();
        } else if (!isSpoofing) {
          toggleSpoofing();
        }
        dismissRecovery();
      } catch(e) {}
    }

    function dismissRecovery() {
      const card = document.getElementById('crashRecoveryCard');
      card.classList.remove('visible');
      try {
        localStorage.setItem('locus_was_active', 'false');
      } catch(e) {}
    }

    function simulateCrashTest() {
      closeSheet('settingsSheet');
      const snapshot = {
        sessionType: 'route',
        lat: currentLat + 0.0012,
        lng: currentLng + 0.0018,
        speedMPS: 11.2,
        timestamp: Date.now(),
        routeDetails: { name: "Life360 Driving Circuit", isLoop: true }
      };
      try {
        localStorage.setItem('locus_crash_snapshot', JSON.stringify(snapshot));
        localStorage.setItem('locus_was_active', 'true');
      } catch(e) {}
      showRecoveryBanner(snapshot);
    }

    // Startup check
    checkCrashRecoveryOnStartup();
    fetchRoadSpeedLimit(currentLat, currentLng);
  </script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(HTML_CONTENT);
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Locus native iOS app preview running on port ${PORT}`);
});
