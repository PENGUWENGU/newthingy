const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = process.env.PORT || 3000;
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.gpx': 'application/gpx+xml',
  '.swift': 'text/plain; charset=utf-8'
};

function getFilesRecursively(dir, base = '') {
  let results = [];
  if (!fs.existsSync(dir)) return results;
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const fullPath = path.join(dir, file);
    const relPath = path.join(base, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(getFilesRecursively(fullPath, relPath));
    } else {
      results.push({
        name: file,
        path: relPath,
        size: stat.size,
        modified: stat.mtime
      });
    }
  });
  return results;
}

const server = http.createServer((req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // API Endpoints
  if (pathname === '/api/info') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      app: 'Locus',
      version: '1.0.0',
      description: 'iOS GPS Simulation, Location Testing & Route Spoofing Studio',
      modes: ['walk', 'sidewalk', 'run', 'cycle', 'bus', 'drive'],
      features: [
        'Liquid Glass Apple-style theme with reactive custom color hexes',
        'Authentic human gait simulation with 6% cadence stride variance and lateral sway',
        'Smart Bus Mode using MapKit & Google Maps transit stop clustering',
        'Smart Car Mode with intelligent stoplight & intersection detection',
        'Instant Speed conversion (mph, km/h, m/s) with robust input validation',
        'Compact draggable floating joystick control',
        'Toolbar quick-action Delete All Points button',
        'Live Activity & Route Completion Banner with green flash, haptics, and persistent summary'
      ]
    }));
    return;
  }

  if (pathname === '/api/swift-sources') {
    const locusDir = path.join(__dirname, 'Locus');
    const files = getFilesRecursively(locusDir);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ files }));
    return;
  }

  if (pathname === '/api/swift-file') {
    const filePath = parsedUrl.query.path;
    if (!filePath || filePath.includes('..')) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid path' }));
      return;
    }
    const fullPath = path.join(__dirname, 'Locus', filePath);
    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()) {
      const content = fs.readFileSync(fullPath, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(content);
    } else {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'File not found' }));
    }
    return;
  }

  if (pathname === '/api/export-gpx') {
    const query = parsedUrl.query;
    const name = query.name || 'Locus Simulated Route';
    const coordsStr = query.coords || '';
    let coords = [];
    try {
      if (coordsStr) coords = JSON.parse(coordsStr);
    } catch (e) {
      coords = [];
    }

    if (coords.length === 0) {
      coords = [
        { lat: 37.7749, lon: -122.4194, time: 0 },
        { lat: 37.7752, lon: -122.4178, time: 30 },
        { lat: 37.7760, lon: -122.4160, time: 65 },
        { lat: 37.7771, lon: -122.4145, time: 105 }
      ];
    }

    const now = new Date();
    let gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Locus iOS GPS Studio" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>${escapeXml(name)}</name>
    <time>${now.toISOString()}</time>
    <desc>Simulated route with human pacing and smart intersection detection</desc>
  </metadata>
  <trk>
    <name>${escapeXml(name)}</name>
    <trkseg>
`;
    coords.forEach((pt, i) => {
      const ptTime = new Date(now.getTime() + (pt.time || i * 5) * 1000).toISOString();
      gpx += `      <trkpt lat="${pt.lat.toFixed(6)}" lon="${pt.lon.toFixed(6)}">
        <ele>${pt.ele || 12.5}</ele>
        <time>${ptTime}</time>
        <speed>${pt.speed || 1.4}</speed>
      </trkpt>\n`;
    });
    gpx += `    </trkseg>
  </trk>
</gpx>`;

    res.writeHead(200, {
      'Content-Type': 'application/gpx+xml',
      'Content-Disposition': `attachment; filename="${name.replace(/[^a-z0-9]/gi, '_').toLowerCase()}.gpx"`
    });
    res.end(gpx);
    return;
  }

  // Static files in /public
  let reqPath = pathname === '/' ? '/index.html' : pathname;
  let safePath = path.normalize(path.join(PUBLIC_DIR, reqPath));

  if (!safePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end('Access denied');
    return;
  }

  if (!fs.existsSync(safePath) || fs.statSync(safePath).isDirectory()) {
    safePath = path.join(PUBLIC_DIR, 'index.html');
  }

  if (fs.existsSync(safePath)) {
    const ext = path.extname(safePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const content = fs.readFileSync(safePath);
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
});

function escapeXml(str) {
  return str.replace(/[<>&'"]/g, c => {
    switch (c) {
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '&': return '&amp;';
      case '\'': return '&apos;';
      case '"': return '&quot;';
    }
  });
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Locus Web Companion & iOS Simulator running at http://0.0.0.0:${PORT}`);
});
