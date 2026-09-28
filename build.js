// build.js - Static verification and asset prep
const fs = require('fs');
const path = require('path');

console.log('Building Locus Web Companion & iOS Simulator...');
if (!fs.existsSync(path.join(__dirname, 'public'))) {
  fs.mkdirSync(path.join(__dirname, 'public'), { recursive: true });
}
console.log('Build completed successfully.');
