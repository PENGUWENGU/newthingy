const http = require('node:http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Locus - Native iOS GPS Simulation App</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: #0b0f19;
      color: #f1f5f9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 16px;
      max-width: 580px;
      width: 100%;
      padding: 32px;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
    }
    .badge {
      display: inline-block;
      background: #065f46;
      color: #34d399;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.05em;
      text-transform: uppercase;
      padding: 4px 10px;
      border-radius: 9999px;
      margin-bottom: 16px;
    }
    h1 {
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 8px;
      color: #ffffff;
    }
    p.subtitle {
      font-size: 14px;
      color: #94a3b8;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 12px;
      margin-bottom: 24px;
    }
    .item {
      background: #1e293b;
      padding: 12px 16px;
      border-radius: 8px;
      border: 1px solid #334155;
    }
    .item-label {
      font-size: 11px;
      color: #94a3b8;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 4px;
    }
    .item-value {
      font-size: 14px;
      font-weight: 600;
      color: #e2e8f0;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    .footer {
      font-size: 12px;
      color: #64748b;
      border-top: 1px solid #1f2937;
      padding-top: 16px;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Native iOS Project</div>
    <h1>Locus iOS Project</h1>
    <p class="subtitle">Xcode project and unsigned IPA build pipeline configured for sideloading and local development.</p>
    
    <div class="grid">
      <div class="item">
        <div class="item-label">Bundle Identifier</div>
        <div class="item-value">com.chrismack.locus</div>
      </div>
      <div class="item">
        <div class="item-label">Deployment Target</div>
        <div class="item-value">iOS 17.0+</div>
      </div>
      <div class="item">
        <div class="item-label">Architecture</div>
        <div class="item-value">arm64 (iPhone / iPad)</div>
      </div>
      <div class="item">
        <div class="item-label">Workflow Output</div>
        <div class="item-value">LocusPlus-unsigned.ipa</div>
      </div>
    </div>

    <div class="footer">
      This repository is a native Swift iOS application. The GitHub Actions workflow <code>build-unsigned-ipa</code> compiles the application binary and packages the unsigned IPA with validated Mach-O executable and resources.
    </div>
  </div>
</body>
</html>`);
});

const PORT = 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Locus dev status server listening on port ${PORT}`);
});
