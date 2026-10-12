'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const {
  getNodeAutoInstrumentations,
} = require('@opentelemetry/auto-instrumentations-node');
const {
  OTLPTraceExporter,
} = require('@opentelemetry/exporter-trace-otlp-grpc');
const {
  OTLPLogExporter
} = require("@opentelemetry/exporter-logs-otlp-grpc");
const {
  BatchLogRecordProcessor
} = require("@opentelemetry/sdk-logs");
const {
  PeriodicExportingMetricReader
} = require('@opentelemetry/sdk-metrics')
const {
  OTLPMetricExporter
} = require('@opentelemetry/exporter-metrics-otlp-grpc')
const {
  resourceFromAttributes,
} = require('@opentelemetry/resources');
const {
  ATTR_SERVICE_NAME,
} = require('@opentelemetry/semantic-conventions');

const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://alloy:4317';

const metricReader = new PeriodicExportingMetricReader({
  exporter: new OTLPMetricExporter({
    url: process.env.OTEL_EXPORTER_OTLP_METRICS_ENDPOINT || otlpEndpoint
  }),
  exportIntervalMillis: 5000
})

const logReader = new BatchLogRecordProcessor ({
  exporter: new OTLPLogExporter({
    url: process.env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT || otlpEndpoint,
  })
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'node-app',
  }),

  traceExporter: new OTLPTraceExporter({
    url:
      process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT || otlpEndpoint,
  }),
  metricReader,
  logRecordProcessors: [
    logReader
  ],
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

process.on('SIGTERM', async () => {
  try {
    await sdk.shutdown();
  } finally {
    process.exit(0);
  }
});
