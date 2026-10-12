const { metrics } = require('@opentelemetry/api');
const pino = require('pino-http')();
const express = require('express');
const app = express();

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

app.listen(process.env.PORT, () => pino.logger.info(`Listening on ${process.env.PORT}`));

