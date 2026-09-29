const http = require('http');
const PORT = process.env.PORT || 3000;

http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Locus iOS Engine Active');
}).listen(PORT, '0.0.0.0', () => {
  console.log(`Locus dev server listening on port ${PORT}`);
});
