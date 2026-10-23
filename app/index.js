const { metrics } = require('@opentelemetry/api');
const pino = require('pino-http')();
const express = require('express');
const app = express();
let client;

(async () => {
  const { Client }= require('pg');
  client = await new Client().connect()
})();

const meter = metrics.getMeter('node-app');

const requestCount = meter.createCounter(
  'app.http.server.requests', {
    description: 'Number of completed HTTP requests',
    unit: '{request}'
  }
);

const requestDuration = meter.createHistogram(
  'app.http.server.duration', {
    description: 'HTTP server request duration',
    unit: 's'
  }
);

app.use(pino);

app.use((req, res, next) => {
  const startedAt = process.hrtime.bigint();

  res.on('finish', () => {
    const durationSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;

    const attributes = {
      'http.request.method': req.method,
      'http.route': req.route?.path || 'unmatched',
      'http.response.status_code': res.statusCode
    };

    requestCount.add(1, attributes);
    requestDuration.record(durationSeconds, attributes);
  });

  next();
})

app.get('/', (_req, res) => {
  res.send('OK');
});

app.get('/slow', (req, res) => {
  setTimeout(() => {
    req.log.info('Slow response');
    res.send('Slow Response');
  }, 2000);
});

app.get('/error', (req, res) => {
  req.log.error('Intentional error');
  res.status(500).send('Intentional error');
});

app.get('/slow-db', async (req, res) => {
  await client.query('SELECT pg_sleep(3)')
  req.log.info('Slow DB Response');
  res.send('Slow DB Response');
});

app.get('/error-db', async (req, res) => {
  try {
    await client.query('SELECT * FROM nonexistent_table') //This will throw error
  } catch (err) {
    req.log.error({ err }, 'Intentional DB error');
    return res.status(500).send('Intentional DB error');
  }
  res.send('OK')
});

app.listen(process.env.PORT, () => pino.logger.info(`Listening on ${process.env.PORT}`));

