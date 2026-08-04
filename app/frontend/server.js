const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.PORT || 3000;
// Internal, cluster-only (or docker-compose service) address of the backend.
// The browser never talks to this directly - only this server does, via the
// /api proxy below.
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000';

// The browser should always call same-origin relative paths ('/api/...').
// That works identically in docker-compose (this server proxies to
// BACKEND_URL) and in Kubernetes (browser -> ALB -> frontend Service, which
// proxies to the internal backend-svc ClusterIP).
app.get('/env.js', (req, res) => {
  res.type('application/javascript');
  res.send('window.BACKEND_URL = "";');
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'frontend' });
});

app.use('/api', createProxyMiddleware({
  target: BACKEND_URL,
  changeOrigin: true,
}));

app.use(express.static(path.join(__dirname, 'public')));

// SPA catch-all - keep this last, and keep it out of the way of /api and /health.
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => console.log(`Frontend listening on port ${PORT}, proxying /api -> ${BACKEND_URL}`));
