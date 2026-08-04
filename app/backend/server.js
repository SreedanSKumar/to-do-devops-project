const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle Postgres client', err);
});

async function initDb(retries = 10, delayMs = 3000) {
  const ddl = `
    CREATE TABLE IF NOT EXISTS tasks (
      id SERIAL PRIMARY KEY,
      text VARCHAR(140) NOT NULL,
      done BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      await pool.query(ddl);
      console.log('Database ready (tasks table present).');
      return;
    } catch (err) {
      console.error(`DB init attempt ${attempt}/${retries} failed: ${err.message}`);
      if (attempt === retries) throw err;
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
}

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'opsboard_backend_' });

const httpRequestDuration = new client.Histogram({
  name: 'opsboard_backend_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});
register.registerMetric(httpRequestDuration);

const httpRequestsTotal = new client.Counter({
  name: 'opsboard_backend_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});
register.registerMetric(httpRequestsTotal);

app.use((req, res, next) => {
  const endTimer = httpRequestDuration.startTimer();
  res.on('finish', () => {
    // Use req.route when available so /api/tasks/:id doesn't explode cardinality
    const route = req.route ? req.baseUrl + req.route.path : req.path;
    const labels = { method: req.method, route, status_code: res.statusCode };
    endTimer(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ---------------------------------------------------------------------------
// Health / readiness (used by k8s probes and the frontend status indicator)
// ---------------------------------------------------------------------------
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'backend' });
});

app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready', service: 'backend' });
  } catch (err) {
    res.status(503).json({ status: 'not-ready', service: 'backend', error: err.message });
  }
});

// Proxied by the frontend at /api/health so the browser (which never talks
// to the backend Service directly in-cluster) can show live backend status.
app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'backend' });
});

// ---------------------------------------------------------------------------
// Task validation (exported for unit tests)
// ---------------------------------------------------------------------------
function validateTaskText(text) {
  if (typeof text !== 'string') return 'text must be a string';
  const trimmed = text.trim();
  if (trimmed.length === 0) return 'text must not be empty';
  if (trimmed.length > 140) return 'text must be 140 characters or fewer';
  return null;
}

// ---------------------------------------------------------------------------
// Tasks API
// ---------------------------------------------------------------------------
app.get('/api/tasks', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, text, done, created_at AS "createdAt" FROM tasks ORDER BY created_at DESC'
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to load tasks' });
  }
});

app.post('/api/tasks', async (req, res) => {
  const error = validateTaskText(req.body && req.body.text);
  if (error) return res.status(400).json({ error });

  try {
    const { rows } = await pool.query(
      'INSERT INTO tasks (text) VALUES ($1) RETURNING id, text, done, created_at AS "createdAt"',
      [req.body.text.trim()]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to create task' });
  }
});

app.patch('/api/tasks/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'invalid task id' });
  if (typeof req.body.done !== 'boolean') {
    return res.status(400).json({ error: 'done must be a boolean' });
  }

  try {
    const { rows } = await pool.query(
      'UPDATE tasks SET done = $1 WHERE id = $2 RETURNING id, text, done, created_at AS "createdAt"',
      [req.body.done, id]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'task not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to update task' });
  }
});

app.delete('/api/tasks/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'invalid task id' });

  try {
    const { rowCount } = await pool.query('DELETE FROM tasks WHERE id = $1', [id]);
    if (rowCount === 0) return res.status(404).json({ error: 'task not found' });
    res.status(204).end();
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to delete task' });
  }
});

// ---------------------------------------------------------------------------
// Startup / graceful shutdown
// ---------------------------------------------------------------------------
let server;

async function start() {
  await initDb();
  server = app.listen(PORT, () => console.log(`Backend listening on port ${PORT}`));
}

function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  if (server) {
    server.close(() => {
      pool.end().then(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10000).unref();
  } else {
    process.exit(0);
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

if (require.main === module) {
  start().catch((err) => {
    console.error('Fatal startup error:', err);
    process.exit(1);
  });
}

module.exports = { app, validateTaskText };
